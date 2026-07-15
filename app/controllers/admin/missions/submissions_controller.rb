module Admin
  module Missions
    class SubmissionsController < BaseController
      layout "application"

      skip_before_action :authorize_mission_management
      before_action :release_other_claims, only: [ :next, :claim ]
      before_action :set_submission, only: [ :show, :update, :claim, :undo ]
      before_action :set_body_class

      def overview
        authorize Mission::Submission, :index?
        @missions = if global_reviewer?
          Mission.enabled.order(:name)
        else
          Mission.enabled.where(id: current_user.mission_memberships.select(:mission_id)).order(:name)
        end

        pending_counts = Mission::Submission
                           .where(status: "pending", deleted_at: nil)
                           .group(:mission_id)
                           .count

        oldest_pending = Mission::Submission
                           .where(status: "pending", deleted_at: nil)
                           .group(:mission_id)
                           .minimum(Arel.sql("COALESCE(pending_at, created_at)"))

        @mission_stats = @missions.map do |m|
          {
            mission: m,
            pending: pending_counts[m.id] || 0,
            oldest: oldest_pending[m.id]
          }
        end.sort_by { |s| -s[:pending] }
      end

      def index
        authorize Mission::Submission, :index?
        if @mission && !accessible_mission?(@mission)
          redirect_to admin_mission_reviews_path, alert: "You don't have access to review this mission."
          return
        end

        @stats = Mission::Submission.dashboard_stats(mission: @mission)
        @leaderboards = {
          daily: Mission::Submission.leaderboard(:daily, mission: @mission),
          weekly: Mission::Submission.leaderboard(:weekly, mission: @mission),
          alltime: Mission::Submission.leaderboard(:alltime, mission: @mission)
        }

        scope = policy_scope(Mission::Submission)
                  .includes(:reviewed_by, ship_event: { post: [ :user, :project ] })
        scope = scope.where(mission_id: @mission.id) if @mission

        scope = apply_filters(scope)
        @submissions = scope.order(Arel.sql("COALESCE(pending_at, created_at) ASC")).limit(100)
      end

      def show
        authorize @submission
        @reviewed_today = Mission::Submission.reviewed_today(current_user, mission: @mission)
        @versions = @submission.versions.order(created_at: :asc).to_a
        whodunnit_ids = @versions.map(&:whodunnit).compact.uniq
        @whodunnit_users = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
      end

      def update
        authorize @submission
        new_status = params.dig(:mission_submission, :status)
        feedback = params.dig(:mission_submission, :feedback).to_s.strip

        unless %w[approved rejected].include?(new_status)
          redirect_to admin_mission_submission_path(mission_slug, @submission),
                      alert: "Pick approve or reject." and return
        end

        unless @submission.reviewed_by_id == current_user.id
          redirect_to admin_mission_submission_path(mission_slug, @submission),
                      alert: "Claim this submission before reviewing." and return
        end

        if new_status == "rejected" && feedback.blank?
          redirect_to admin_mission_submission_path(mission_slug, @submission),
                      alert: "Provide a rejection reason." and return
        end

        can_transition = (new_status == "approved" && @submission.may_approve?) ||
                         (new_status == "rejected" && @submission.may_reject?)

        unless can_transition
          redirect_to admin_mission_submission_path(mission_slug, @submission),
                      alert: "This submission can't be #{new_status} right now." and return
        end

        Mission::Submission.transaction do
          if new_status == "approved"
            @submission.update!(reviewed_by: current_user, reviewed_at: Time.current, rejection_message: nil)
            @submission.approve!
            grant_mission_achievement_if_configured
            grant_fixed_stardust_if_configured
          else
            @submission.update!(reviewed_by: current_user, reviewed_at: Time.current, rejection_message: feedback)
            @submission.reject!
          end
        end

        notify_builder(new_status)

        reviewed = Mission::Submission.reviewed_today(current_user, mission: @mission)
        redirect_to next_admin_mission_submissions_path(mission_slug),
                    notice: "#{new_status.titleize}. That's #{reviewed} reviewed today."
      end

      def next
        authorize Mission::Submission, :index?
        if @mission && !accessible_mission?(@mission)
          redirect_to admin_mission_reviews_path, alert: "You don't have access to review this mission."
          return
        end
        skip_ids = parse_skip_ids

        missions_filter = if @mission
          @mission
        elsif !global_reviewer?
          current_user.mission_memberships.select(:mission_id)
        end
        candidate = Mission::Submission.next_eligible(current_user, missions: missions_filter, skip_ids: skip_ids)
        unless candidate
          redirect_to admin_mission_submissions_path(mission_slug),
                      notice: "No more submissions to review." and return
        end

        claimed = Mission::Submission.atomic_claim!(candidate.id, current_user)
        if claimed
          redirect_to admin_mission_submission_path(mission_slug, claimed)
        else
          skip_ids << candidate.id
          redirect_to next_admin_mission_submissions_path(mission_slug, skip: skip_ids.join(","))
        end
      end

      def claim
        authorize @submission, :claim?
        claimed = Mission::Submission.atomic_claim!(@submission.id, current_user)
        if claimed
          redirect_to admin_mission_submission_path(mission_slug, claimed)
        else
          redirect_to admin_mission_submissions_path(mission_slug),
                      alert: "Could not claim this submission."
        end
      end

      def undo
        authorize @submission
        Mission::Submission.transaction do
          @submission.update!(reviewed_by: nil, reviewed_at: nil, rejection_message: nil)
          @submission.undo!
          reverse_fixed_stardust_if_granted
          revoke_mission_achievement_if_granted
        end
        redirect_to admin_mission_submission_path(mission_slug, @submission),
                    notice: "Submission moved back to pending."
      end

      private

      # Path segment for redirects: the mission's slug, or "all" for the
      # cross-mission queue.
      def mission_slug
        @mission&.slug || "all"
      end

      # Cross-mission views (overview, or slug "all") run with @mission nil.
      def set_mission
        slug = params[:mission_slug] || params[:slug]
        if slug.blank? || slug == "all"
          @mission = nil
        else
          @mission = Mission.with_deleted.find_by!(slug: slug)
        end
      end

      def accessible_mission?(mission)
        return true if global_reviewer?

        mission.memberships.exists?(user_id: current_user.id)
      end

      # Admins and global mission reviewers can review any mission; everyone
      # else (helpers included) is scoped to missions they're a member of.
      def global_reviewer?
        current_user.admin? || current_user.has_role?(:mission_reviewer)
      end

      def set_submission
        if @mission
          @submission = @mission.submissions.find(params[:id])
        else
          @submission = Mission::Submission.find(params[:id])
          @mission = @submission.mission
        end
      end

      def set_body_class
        @body_class = "app-layout-page"
      end

      def pundit_namespace(record)
        record
      end

      def release_other_claims
        Mission::Submission.release_all_for(current_user) if current_user
      end

      def parse_skip_ids
        params[:skip].to_s.split(",").map(&:to_i).reject(&:zero?)
      end

      def apply_filters(scope)
        status = params[:status]
        valid_states = Mission::Submission.aasm.states.map(&:name).map(&:to_s)
        if status.present? && valid_states.include?(status)
          scope = scope.where(status: status)
        elsif status != "all"
          scope = scope.where(status: "pending")
        end
        if params[:search].present?
          term = ActiveRecord::Base.sanitize_sql_like(params[:search].strip)
          scope = scope.joins(ship_event: { post: :project })
                       .where("projects.title ILIKE ?", "%#{term}%")
        end
        scope
      end

      def grant_mission_achievement_if_configured
        mission = @submission.mission
        return if mission.achievement_slug.blank?
        builder = @submission.ship_event&.post&.user
        return unless builder

        return if builder.achievements.exists?(achievement_slug: mission.achievement_slug)

        builder.achievements.create!(
          achievement_slug: mission.achievement_slug,
          earned_at: Time.current
        )
      end

      def revoke_mission_achievement_if_granted
        mission = @submission.mission
        return if mission.achievement_slug.blank?
        builder = @submission.ship_event&.post&.user
        return unless builder

        builder.achievements.where(achievement_slug: mission.achievement_slug).destroy_all
      end

      def grant_fixed_stardust_if_configured
        mission = @submission.mission
        return unless mission.fixed_stardust_payout&.positive?
        return unless @submission.ledger_entries.sum(:amount).zero?
        builder = @submission.ship_event&.post&.user
        return unless builder

        @submission.ledger_entries.create!(
          user: builder,
          amount: mission.fixed_stardust_payout,
          reason: "Mission: #{mission.name}",
          created_by: "mission_submission:#{@submission.id} (#{current_user.id})"
        )
      end

      def reverse_fixed_stardust_if_granted
        net = @submission.ledger_entries.sum(:amount)
        return unless net.positive?
        builder = @submission.ship_event&.post&.user
        return unless builder

        @submission.ledger_entries.create!(
          user: builder,
          amount: -net,
          reason: "Mission reversal: #{@submission.mission.name}",
          created_by: "mission_submission:#{@submission.id} undo (#{current_user.id})"
        )
      end

      def notify_builder(status)
        builder = @submission.ship_event&.post&.user
        return unless builder

        klass = status == "approved" ? Notifications::Missions::SubmissionApproved : Notifications::Missions::SubmissionRejected
        klass.notify(recipient: builder, actor: current_user, record: @submission)
      rescue StandardError => e
        Rails.logger.warn("MissionSubmissions notify_builder: #{e.message}")
      end
    end
  end
end
