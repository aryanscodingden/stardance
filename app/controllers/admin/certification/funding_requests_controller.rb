class Admin::Certification::FundingRequestsController < Admin::Certification::ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :release_other_claims, only: [ :next ]
  before_action :set_funding_request, only: [ :show, :update ]
  before_action :set_body_class, only: [ :index, :show, :update ]

  def index
    authorize ::Certification::FundingRequest

    @status = params[:status].presence_in(%w[pending approved returned all]) || "pending"
    @sort = params[:sort] == "newest" ? "newest" : "oldest"
    @search = params[:search].to_s.strip
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])

    scope = policy_scope(::Certification::FundingRequest)
              .includes(:reviewer, project: { memberships: :user })
    scope = scope.where(status: @status) unless @status == "all"
    scope = scope.where("certification_funding_requests.created_at >= ?", @from.beginning_of_day) if @from
    scope = scope.where("certification_funding_requests.created_at <= ?", @to.end_of_day) if @to
    scope = apply_search(scope) if @search.present?

    @pagy, @funding_requests = pagy(:offset,
                                    scope.order(created_at: @sort == "newest" ? :desc : :asc),
                                    limit: 25)

    @stats = ::Certification::FundingRequest.dashboard_stats
    @lb_period = params[:lb].presence_in(%w[daily weekly alltime]) || "daily"
    @leaderboards = {
      "daily" => ::Certification::FundingRequest.leaderboard(:daily),
      "weekly" => ::Certification::FundingRequest.leaderboard(:weekly),
      "alltime" => ::Certification::FundingRequest.leaderboard(:alltime)
    }
  end

  def show
    authorize @funding_request
    @reviewed_today = ::Certification::FundingRequest.reviewed_today(current_user)
    @lapse_timelapses = lapse_timelapses_for_review
    @lookout_recordings = lookout_recordings_for_review
  end

  def update
    authorize @funding_request
    if @funding_request.update(funding_request_params)
      verb = @funding_request.approved? ? "Approved" : "Returned"
      count = ::Certification::FundingRequest.reviewed_today(current_user)
      redirect_to next_admin_certification_funding_requests_path,
                  notice: "#{verb} funding for “#{@funding_request.project.title}.” That's #{count} reviewed today. Keep going!"
    else
      @reviewed_today = ::Certification::FundingRequest.reviewed_today(current_user)
      @lapse_timelapses = lapse_timelapses_for_review
      @lookout_recordings = lookout_recordings_for_review
      render :show, status: :unprocessable_entity
    end
  end

  def next
    authorize ::Certification::FundingRequest
    skip_ids = parse_skip_ids
    candidate = ::Certification::FundingRequest.next_eligible(current_user, skip_ids: skip_ids)
    if candidate.nil?
      redirect_to admin_certification_funding_requests_path, notice: "Queue is empty." and return
    end
    claimed = ::Certification::FundingRequest.atomic_claim!(candidate.id, current_user)
    if claimed
      redirect_to admin_certification_funding_request_path(claimed)
    else
      new_skip = (skip_ids + [ candidate.id ]).uniq
      redirect_to next_admin_certification_funding_requests_path(skip: new_skip.join(","))
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

  def release_other_claims
    ::Certification::FundingRequest.release_all_for(current_user) if current_user.present?
  end

  def parse_skip_ids
    params[:skip].to_s.split(",").map(&:to_i).reject(&:zero?)
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Numeric input matches a review id or a project title; text matches title.
  def apply_search(scope)
    if @search.match?(/\A\d+\z/)
      scope.where("certification_funding_requests.id = :id OR projects.title ILIKE :q",
                  id: @search.to_i, q: "%#{@search}%")
    else
      scope.where("projects.title ILIKE ?", "%#{@search}%")
    end
  end

  def funding_request_params
    params.require(:certification_funding_request).permit(:status, :feedback, :approved_amount_dollars)
  end
end
