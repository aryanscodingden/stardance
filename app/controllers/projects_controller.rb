class ProjectsController < ApplicationController
  before_action :set_project_minimal, only: [ :edit, :update, :destroy, :mark_fire, :unmark_fire ]
  before_action :set_project, only: [ :show, :readme ]

  def show
    authorize @project

    @body_class = "app-layout-page"
    prepare_project_show_context
  end

  def prepare_project_show_context
    @members = @project.users.to_a
    @is_member = current_user && @members.include?(current_user)
    @active_nav_slug = @is_member ? "projects" : "home"
    @can_edit_project = @is_member && policy(@project).update?
    @follower_count = @project.project_follows.size
    @viewer_follow = current_user && @project.project_follows.find_by(user_id: current_user.id)
    @total_hours = (@project.duration_seconds / 3600.0).round

    if @is_member && current_user
      @composer_devlog = Post::Devlog.new
      @composer_projects = current_user.projects.order(updated_at: :desc)

      @hackatime_linked = current_user.hackatime_identity.present?

      if @hackatime_linked
        @linked_hackatime_projects = @project.hackatime_projects
        @all_hackatime_projects = current_user.hackatime_projects.includes(:project)
        result = current_user.try_sync_hackatime_data!
        @hackatime_times = result&.dig(:projects) || {}

        linked_ids = @linked_hackatime_projects.map(&:id).to_set
        @hackatime_dropdown_items = @all_hackatime_projects.map do |hp|
          seconds = @hackatime_times[hp.name] || 0
          taken = hp.project_id.present? && hp.project_id != @project.id
          {
            id: hp.id,
            name: hp.name,
            seconds: seconds,
            hours: (seconds / 3600.0).round(1),
            taken: taken,
            taken_by: taken ? hp.project&.title : nil,
            linked: linked_ids.include?(hp.id)
          }
        end
      end
    end


    load_posts = -> {
      @project.posts
               .includes(postable: [ :attachments_attachments ])
               .order(created_at: :desc)
               .select { |post| post.postable.present? }
    }

    @posts = if current_user&.can_see_deleted_devlogs?
      Post::Devlog.unscoped { load_posts.call }
    else
      load_posts.call
    end

    unless current_user && Flipper.enabled?(:"git_commit_2025-12-25", current_user)
      @posts = @posts.reject { |post| post.postable_type == "Post::GitCommit" }
    end

    unless current_user&.admin?
      @posts = @posts.reject { |post| post.postable_type == "Post::ShipEvent" && post.postable.certification_status != "approved" }
    end

    @show_project_onboarding = @is_member && @posts.empty?
    @show_hackatime_onboarding = @show_project_onboarding && current_user && current_user.hackatime_identity.blank?
    @project_onboarding_mission = @project.current_mission

    if current_user
      devlog_ids = @posts.select { |p| p.postable_type == "Post::Devlog" }.map(&:postable_id)
      @liked_devlog_ids = Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_ids).pluck(:likeable_id).to_set
    else
      @liked_devlog_ids = Set.new
    end

    ahoy.track "Viewed project", project_id: @project.id

    @latest_ship_post = @posts.find { |post| post.postable_type == "Post::ShipEvent" }
    latest_ship_event = @latest_ship_post&.postable

    @votes_for_payout = nil
    if current_user.present?
      is_owner = @project.memberships.where(role: :owner, user_id: current_user.id).exists?

      @show_ai_coding_time_ignored_card = is_owner && !current_user.has_dismissed?("ai_coding_time_ignored_card")

      if is_owner &&
          latest_ship_event.present? &&
          latest_ship_event.certification_status == "approved" &&
          latest_ship_event.payout.blank?

        required = Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT
        current = latest_ship_event.votes.payout_countable.count
        remaining = [ required - current, 0 ].max

        @votes_for_payout = {
          current: current,
          required: required,
          remaining: remaining
        }
      end
    end
  end
  private :prepare_project_show_context

  def new
    @project = Project.new
    authorize @project
    @missions = Mission.available
                       .includes(:icon_attachment, :banner_attachment)
                       .order(featured_at: :desc)
                       .limit(8)
  end

  def create
    @project = Project.new(project_params)
    authorize @project

    validate_urls
    success = false

    Project.transaction do
      break unless @project.errors.empty? && @project.save

      @project.memberships.create!(user: current_user, role: :owner)
      link_hackatime_projects

      if @project.errors.empty?
        success = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if success
      flash[:notice] = "Project created successfully"
      current_user.complete_tutorial_step! :create_project

      unless @project.tutorial?
        existing_non_tutorial_projects = current_user.projects.where(tutorial: false).where.not(id: @project.id)
        if existing_non_tutorial_projects.empty?
          FunnelTrackerService.track(
            event_name: "project_created",
            user: current_user,
            properties: { project_id: @project.id }
          )
        end
      end

      project_hours = @project.total_hackatime_hours
      # if project_hours > 0
      #   tutorial_message OnboardingCopy::PROJECT_CREATED_WITH_HOURS.call(
      #     helpers.distance_of_time_in_words(project_hours.hours)
      #   )
      # else
      #   tutorial_message OnboardingCopy::PROJECT_CREATED_NO_HOURS
      # end

      if (slug = params[:mission_slug].presence)
        mission = Mission.find_by(slug: slug)
        @project.missions << mission if mission
      end

      redirect_to project_path(@project)
    else
      flash[:alert] = "Failed to create project: #{@project.errors.full_messages.join(', ')}"
      @missions = Mission.available
                         .includes(:icon_attachment, :banner_attachment)
                         .order(featured_at: :desc)
                         .limit(8)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project
    load_project_times
  end

  def update
    authorize @project

    @project.assign_attributes(project_params)
    validate_urls
    success = @project.errors.empty? && @project.save

    link_hackatime_projects if success
    # 2nd check w/ @project.errors.empty? is not redudant. this is ensures that hackatime is linked!
    if success && @project.errors.empty?
      flash[:notice] = "Project updated successfully"
      redirect_to url_from(params[:return_to]) || project_path(@project)
    else
      flash.now[:alert] = "Failed to update project: #{@project.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    authorize @project
    force = params[:force] == "true" && policy(@project).force_destroy?

    begin
      if force && @project.shipped?
        PaperTrail::Version.create!(
          item_type: "Project",
          item_id: @project.id,
          event: "force_delete",
          whodunnit: current_user.id,
          object_changes: {
            deleted_at: [ nil, Time.current ],
            shipped_at: @project.shipped_at,
            reason: "Admin/Fraud override of ship protection",
            deleted_by: current_user.id
          }.to_yaml
        )
      end

      @project.soft_delete!(force: force)
      current_user.revoke_tutorial_step! :create_project if current_user.projects.empty?
      flash[:notice] = "Project deleted successfully"
      redirect_to projects_user_path(current_user)
    rescue ActiveRecord::RecordInvalid => e
      flash[:alert] = e.record.errors.full_messages.to_sentence
      redirect_to project_path(@project)
    end
  end

  def mark_fire
    authorize :admin, :manage_projects?

    return render(json: { message: "Project not found" }, status: :not_found) unless @project

    if @project.users.include?(current_user)
      return render(json: { message: "You cannot mark your own project as a Super Star." }, status: :forbidden)
    end

    if current_user.fraud_dept? && !current_user.admin?
      if @project.users.any? { |u| u.fraud_dept? }
        return render(json: { message: "You cannot mark a fellow fraud department member's project as a Super Star." }, status: :forbidden)
      end
    end

    PaperTrail.request(whodunnit: current_user.id) do
      fire_event = Post::FireEvent.create(
        body: "⭐ #{current_user.display_name} marked your project as a Super Star! As a prize for your great work, look out for a bonus prize in the mail :)"
      )

      unless fire_event.persisted?
        render json: { message: fire_event.errors.full_messages.to_sentence.presence || "Failed to mark project as a Super Star" }, status: :unprocessable_entity
        next
      end

      post = @project.posts.create(user: current_user, postable: fire_event)

      if post.persisted?
        @project.mark_fire!(current_user)

        PaperTrail::Version.create!(
          item_type: "Project",
          item_id: @project.id,
          event: "mark_fire",
          whodunnit: current_user.id,
          object_changes: {
            admin_action: [ nil, "mark_fire" ],
            marked_fire_by_id: [ nil, current_user.id ],
            created_post_id: [ nil, post.id ]
          }
        )

        Project::PostToMagicJob.perform_later(@project)
        Project::MagicHappeningLetterJob.perform_later(@project)

        @project.users.each do |user|
          SendSlackDmJob.perform_later(
            user.slack_id,
            blocks_path: "notifications/projects/super_star",
            locals: { project: @project }
          )
        end

        render json: { message: "Project marked as ⭐!", fire: true }, status: :ok
      else
        errors = (post.errors.full_messages + fire_event.errors.full_messages).uniq
        render json: { message: errors.to_sentence.presence || "Failed to mark project as a Super Star" }, status: :unprocessable_entity
      end
    end
  end

  def unmark_fire
    authorize :admin, :manage_projects?

    return render(json: { message: "Project not found" }, status: :not_found) unless @project

    PaperTrail.request(whodunnit: current_user.id) do
      @project.unmark_fire!

      PaperTrail::Version.create!(
        item_type: "Project",
        item_id: @project.id,
        event: "unmark_fire",
        whodunnit: current_user.id,
        object_changes: {
          admin_action: [ nil, "unmark_fire" ]
        }
      )

      render json: { message: "Project unmarked as Super Star", fire: false }, status: :ok
    end
  end

  def follow
    return redirect_to(project_path(params[:id]), alert: "Please sign in first.") unless current_user

    @project = Project.find(params[:id])
    authorize @project, :show?

    follow = current_user.project_follows.build(project: @project)
    if follow.save
      @project.users.includes(:preference).each do |member|
        if member.preference.send_notifications_for_new_followers && current_user.slack_id && member.slack_id
          SendSlackDmJob.perform_later(
            member.slack_id,
            "#{current_user.display_name} is now following your project #{@project.title}!",
            blocks_path: "notifications/new_follower",
            locals: {
              project_title: @project.title,
              project_url: project_url(@project, host: "flavortown.hackclub.com", protocol: "https"),
              follower_id: current_user.slack_id
            }
          )
        end
      end
      redirect_to project_path(@project), notice: "You are now following this project."
    else
      redirect_to project_path(@project), alert: follow.errors.full_messages.to_sentence
    end
  end

  def unfollow
    return redirect_to(project_path(params[:id]), alert: "Please sign in first.") unless current_user

    @project = Project.find(params[:id])
    authorize @project, :show?

    follow = current_user.project_follows.find_by(project: @project)
    if follow&.destroy
      redirect_to project_path(@project), notice: "You have unfollowed this project."
    else
      redirect_to project_path(@project), alert: "Could not unfollow."
    end
  end

  def readme
    unless turbo_frame_request?
      redirect_to project_path(@project)
      return
    end

    result = ProjectReadmeFetcher.fetch(@project.readme_url)

    @readme_html =
      if result.markdown.present?
        html = MarkdownRenderer.render(result.markdown)
        ReadmeHtmlRewriter.rewrite(html: html, readme_url: @project.readme_url)
      end

    @readme_error = result.error

    render "projects/readme", layout: false
  end

  private

  # These are the same today, but they'll be different tomorrow.

  def set_project
    @project = Project.find(params[:id])
  end

  def set_project_minimal
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:title, :description, :demo_url, :repo_url, :readme_url, :banner, :ai_declaration)
  end

  def hackatime_project_ids
    @hackatime_project_ids ||= Array(params[:project][:hackatime_project_ids]).reject(&:blank?).map(&:to_i)
  end

  def validate_urls
    if @project.demo_url.blank? && @project.repo_url.blank? && @project.readme_url.blank?
      return
    end


    if @project.demo_url.present? && @project.repo_url.present?
      if @project.demo_url == @project.repo_url || @project.demo_url == @project.readme_url
        @project.errors.add(:base, "Demo URL and Repository URL cannot be the same")
      end
    end

    validate_url_not_dead(:demo_url, "Demo URL") if @project.demo_url.present? && @project.errors.empty?

    validate_url_not_dead(:repo_url, "Repository URL") if @project.repo_url.present? && @project.errors.empty?
    validate_url_not_dead(:readme_url, "Readme URL") if @project.readme_url.present? && @project.errors.empty?
  end

  # these links block automated requests, but we're ok with just assuming they're good
  ALLOWLISTED_DOMAINS = %w[
    npmjs.com
    crates.io
    curseforge.com
    makerworld.com
    streamlit.app
  ].freeze

  def validate_url_not_dead(attribute, name)
    require "uri"
    require "faraday"
    require "faraday/follow_redirects"

    return unless @project.send(attribute).present?

    uri = URI.parse(@project.send(attribute))

    if ALLOWLISTED_DOMAINS.any? { |domain| uri.host&.end_with?(domain) }
      return
    end

    conn = Faraday.new(
      url: uri.to_s,
      headers: { "User-Agent" => "Stardance project validator (https://flavortown.hackclub.com/)" }
    ) do |faraday|
      faraday.response :follow_redirects, max_redirects: 3
      faraday.adapter Faraday.default_adapter
    end
    response = conn.get() do |req|
      req.options.timeout = 5
      req.options.open_timeout = 5
    end

    unless (200..299).cover?(response.status)
      @project.errors.add(attribute, "Your #{name} needs to return a 200 status. I got #{response.status}, is your code/website set to public!?!?")
    end


    # Copy pasted from https://github.com/hackclub/summer-of-making/blob/29e572dd6df70627d37f3718a6ebd4bafb07f4c7/app/controllers/projects_controller.rb#L275
    if attribute != :demo_url
      repo_patterns = [
        %r{/blob/}, %r{/tree/}, %r{/src/}, %r{/raw/}, %r{/commits/},
        %r{/pull/}, %r{/issues/}, %r{/compare/}, %r{/releases/},
        /\.git$/, %r{/commit/}, %r{/branch/}, %r{/blame/},

        %r{/projects/}, %r{/repositories/}, %r{/gitea/}, %r{/cgit/},
        %r{/gitweb/}, %r{/gogs/}, %r{/git/}, %r{/scm/},

        /\.(md|py|js|ts|jsx|tsx|html|css|scss|php|rb|go|rs|java|cpp|c|h|cs|swift)$/
      ]

      # Known code hosting platforms (not required, but used for heuristic)
      known_platforms = [
        "github", "gitlab", "bitbucket", "dev.azure", "sourceforge",
        "codeberg", "sr.ht", "replit", "vercel", "netlify", "glitch",
        "hackclub", "gitea", "git", "repo", "code"
      ]

      path = uri.path.downcase
      host = uri.host.downcase

      is_valid_repo_url = false

      if repo_patterns.any? { |pattern| path.match?(pattern) }
        is_valid_repo_url = true
      elsif attribute == :readme_url && (host.include?("raw.githubusercontent") || path.include?("/readme") || path.end_with?(".md") || path.end_with?("readme.txt"))
        is_valid_repo_url = true
      elsif known_platforms.any? { |platform| host.include?(platform) }
        is_valid_repo_url = path.split("/").size > 2
      elsif path.split("/").size > 1 && path.exclude?("wp-") && path.exclude?("blog")
        is_valid_repo_url = true
      end

      unless is_valid_repo_url
        @project.errors.add(attribute, "#{name} does not appear to be a valid repository or project URL")
      end
    end

  rescue URI::InvalidURIError
    @project.errors.add(attribute, "#{name} is not a valid URL")
  rescue Faraday::ConnectionFailed => e
    @project.errors.add(attribute, "Please make sure the URL is valid and reachable: #{e.message}")
  rescue StandardError => e
    @project.errors.add(attribute, "#{name} could not be verified (idk why, pls let a admin know if this is happening a lot and your sure that the URL is valid): #{e.message}")
  end

  def link_hackatime_projects
    # Unlink hackatime projects that were removed
    @project.hackatime_projects.where.not(id: hackatime_project_ids).find_each do |hp|
      hp.update(project: nil)
    end

    return if hackatime_project_ids.empty?

    current_user.hackatime_projects.where(id: hackatime_project_ids).find_each do |hp|
      unless hp.update(project: @project)
        hp.errors.full_messages.each do |message|
          @project.errors.add(:base, "Hackatime project #{hp.name}: #{message}")
        end
      end
    end
  end

  def load_project_times
    result = current_user.try_sync_hackatime_data!
    @project_times = result&.dig(:projects) || {}
  end
end
