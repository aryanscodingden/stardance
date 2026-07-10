class Admin::Certification::FundingRequestsController < Admin::Certification::ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_funding_request
  before_action :set_body_class

  def update
    authorize @funding_request
    if @funding_request.update(funding_request_params)
      verb = @funding_request.approved? ? "Approved" : "Returned"
      count = ::Certification::FundingRequest.reviewed_today(current_user)
      notice = "#{verb} funding for “#{@funding_request.project.title}.” That's #{count} reviewed today. Keep going!"
      redirect_to admin_certification_hardware_review_path(@funding_request.project_id), notice: notice
    else
      load_hardware_review_context
      render "admin/certification/hardware_reviews/show", status: :unprocessable_entity
    end
  end

  private

  def set_funding_request
    @funding_request = ::Certification::FundingRequest.find(params[:id])
  end

  # Both fetches below fan out to live HTTP (per Hackatime key / Lookout session)
  # on every render, including the re-render after a failed verdict submit. The
  # provider URLs only expire after ~1h, so a short cache keyed by project kills
  # the repeat fan-out without meaningfully staling them.
  RECORDINGS_CACHE_TTL = 1.minute

  # Lapse timelapses the builder recorded for *this* project, joined via the
  # project's Hackatime keys and the submitter's Hackatime id so reviewers see
  # the videos tied to the submission rather than the builder's whole library.
  # Returns [] when the submitter has no Hackatime link or the project has no
  # linked Hackatime keys.
  def lapse_timelapses_for_review
    Rails.cache.fetch(recordings_cache_key("lapse"), expires_in: RECORDINGS_CACHE_TTL) do
      LapseService.timelapses_for_project(
        hackatime_user_id: @funding_request.owner&.hackatime_identity&.uid,
        project_keys: @funding_request.project.hackatime_keys
      )
    end
  end

  # The project's finished Lookout screen recordings, refreshed live (Lookout's
  # stored video URLs expire). Returns [] when the project has none.
  def lookout_recordings_for_review
    Rails.cache.fetch(recordings_cache_key("lookout"), expires_in: RECORDINGS_CACHE_TTL) do
      LookoutService.recordings_for_project(@funding_request.project)
    end
  end

  def recordings_cache_key(source)
    [ "funding_review_recordings", source, @funding_request.project_id ]
  end

  # The .app-layout wrapper reserves the sidebar gutter itself; this body class
  # zeroes the body's own sidebar margin so the two don't stack into a huge gap.
  def set_body_class
    @body_class = "app-layout-page"
  end

  def load_hardware_review_context
    @project = @funding_request.project
    @ship = @project.ship_reviews.order(created_at: :desc).first
    @owner = @project.memberships.owner.first&.user
    @active_review = @funding_request
    @active_review_type = :funding
    @reviewed_today = ::Certification::FundingRequest.reviewed_today(current_user) +
                      ::Certification::Ship.reviewed_today(current_user)
    @lapse_timelapses = lapse_timelapses_for_review
    @lookout_recordings = lookout_recordings_for_review
  end

  def funding_request_params
    params.require(:certification_funding_request).permit(:status, :feedback, :approved_amount_dollars)
  end
end
