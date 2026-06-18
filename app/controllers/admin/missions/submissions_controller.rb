module Admin
  module Missions
    class SubmissionsController < BaseController
      layout "application"

      before_action :release_other_claims, only: [ :next, :claim ]
      before_action :set_submission, only: [ :show, :update, :claim, :undo ]
      before_action :set_body_class

      def overview
        authorize Mission::Submission, :index?
        @missions = Mission.enabled.order(:name)

        pending_counts = Mission::Submission
                           .where(status: "pending", deleted_at: nil)
                           .group(:mission_id)
                           .count

        oldest_pending = Mission::Submission
                           .where(status: "pending", deleted_at: nil)
                           .group(:mission_id)
                           .minimum(:created_at)

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
        @submissions = scope.order(created_at: :asc).limit(100)
      end

      def show
        authorize @submission
        @reviewed_today = Mission::Submission.reviewed_today(current_user, mission: @mission)
        @devlogs = load_devlogs_since_last_ship
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

        Mission::Submission.transaction do
          @submission.update!(reviewed_by: current_user, reviewed_at: Time.current,
                              rejection_message: new_status == "rejected" ? feedback : nil)

          if new_status == "approved"
            @submission.approve!
            grant_mission_achievement_if_configured
            grant_fixed_stardust_if_configured
          elsif new_status == "rejected"
            @submission.reject!
          end
        end

        notify_builder(new_status == "approved" ? "submission_approved" : "submission_rejected")

        reviewed = Mission::Submission.reviewed_today(current_user, mission: @mission)
        redirect_to next_admin_mission_submissions_path(mission_slug),
                    notice: "#{new_status.titleize}. That's #{reviewed} reviewed today."
      end

      def next
        authorize Mission::Submission, :index?
        skip_ids = parse_skip_ids

        candidate = Mission::Submission.next_eligible(current_user, mission: @mission, skip_ids: skip_ids)
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

      def authorize_mission_management
        if @mission
          authorize @mission, :manage?
        else
          authorize Mission::Submission, :index?
        end
      rescue Pundit::NotAuthorizedError
        authorize Mission::Submission, :index?
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

      def load_devlogs_since_last_ship
        project = @submission.ship_event&.post&.project
        return [] unless project

        previous_ship = project.posts
          .where(postable_type: "Post::ShipEvent")
          .where.not(postable_id: @submission.ship_event_id)
          .order(created_at: :desc)
          .first

        scope = project.posts
          .where(postable_type: "Post::Devlog")
          .includes(:postable, :user)
          .order(created_at: :desc)

        scope = scope.where("posts.created_at > ?", previous_ship.created_at) if previous_ship
        scope.to_a
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
          term = sanitize_sql_like(params[:search].strip)
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

      def notify_builder(template_basename)
        builder = @submission.ship_event&.post&.user
        return unless builder&.slack_id.present?

        SendSlackDmJob.perform_later(
          builder.slack_id,
          blocks_path: "notifications/missions/#{template_basename}.slack_message",
          locals: @submission.notification_locals
        )
      rescue StandardError => e
        Rails.logger.warn("MissionSubmissions notify_builder: #{e.message}")
      end
    end
  end
end
