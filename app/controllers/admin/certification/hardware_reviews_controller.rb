# frozen_string_literal: true

# Unified hardware review queue and project page. A hardware project moves
# through design funding and build certification, but reviewers should see one
# queue and one active review at a time. Mutations still go through the existing
# funding/ship endpoints so PaperTrail remains attached to the underlying record.
class Admin::Certification::HardwareReviewsController < Admin::Certification::ApplicationController
  before_action -> { head :not_found unless Flipper.enabled?(:hardware_flow, current_user) }
  before_action :set_project, only: [ :show ]
  before_action -> { head :not_found unless @project.hardware? }, only: [ :show ]
  before_action :set_body_class

  # GET /admin/certification/hardware
  def index
    authorize Project, policy_class: Admin::Certification::HardwareReviewPolicy

    @status = params[:status].presence_in(%w[pending approved returned all]) || "pending"
    @sort = params[:sort] == "newest" ? "newest" : "oldest"
    @search = params[:search].to_s.strip
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])
    @stage = params[:stage].presence_in(%w[design build]).to_s
    @lb_period = params[:lb].presence_in(%w[daily weekly alltime]) || "daily"

    funding_scope = apply_queue_filters(hardware_funding_list_scope, ::Certification::FundingRequest)
    ship_scope = apply_queue_filters(hardware_ship_list_scope, ::Certification::Ship)

    @stage_counts = {
      "design" => funding_scope.count,
      "build" => ship_scope.count
    }

    funding_scope = funding_scope.none if @stage == "build"
    ship_scope = ship_scope.none if @stage == "design"

    funding_items = funding_scope.includes(:reviewer, project: { memberships: :user }).map do |request|
      review_item(:funding, request, request.project, request.owner, request.created_at)
    end

    ship_items = ship_scope.includes(:reviewer, project: { memberships: :user, posts: :postable }).map do |ship|
      review_item(:ship, ship, ship.project, ship.owner, ship.created_at)
    end

    @review_items = sort_review_items(funding_items + ship_items)
    @hackpad_project_ids = hackpad_project_ids(@review_items.map { |item| item[:project].id })
    @stats = hardware_queue_stats
    @leaderboards = {
      "daily" => hardware_leaderboard(:daily),
      "weekly" => hardware_leaderboard(:weekly),
      "alltime" => hardware_leaderboard(:alltime)
    }
    @reviewed_today = reviewed_today_count
  end

  # GET /admin/certification/hardware/next
  def next
    authorize Project, policy_class: Admin::Certification::HardwareReviewPolicy

    skip = parse_skip_tokens
    candidate = next_candidate(skip)
    if candidate.nil?
      redirect_to admin_certification_hardware_reviews_path, notice: "Hardware queue is empty." and return
    end

    claimed = claim_candidate(candidate)
    if claimed
      redirect_to admin_certification_hardware_review_path(claimed.project_id)
    else
      redirect_to next_admin_certification_hardware_reviews_path(skip: (skip[:tokens] + [ candidate[:token] ]).join(","))
    end
  end

  # GET /admin/certification/hardware/:project_id
  def show
    authorize @project, policy_class: Admin::Certification::HardwareReviewPolicy

    load_review_context
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def review_owner
    @review_owner ||= @project.memberships.owner.first&.user
  end

  def load_review_context
    @funding_request = @project.latest_funding_request
    @ship = @project.ship_reviews.order(created_at: :desc).first
    @owner = review_owner
    @active_review =
      if @funding_request&.pending?
        @funding_request
      elsif @ship&.pending?
        @ship
      end
    @active_review_type =
      case @active_review
      when ::Certification::FundingRequest then :funding
      when ::Certification::Ship then :ship
      end
    @reviewed_today = reviewed_today_count
    @lapse_timelapses = lapse_timelapses_for_review
    @lookout_recordings = lookout_recordings_for_review
  end

  def hardware_funding_scope
    ::Certification::FundingRequest.available_for(current_user)
      .joins(:project)
      .where.not(projects: { hardware_stage: nil })
  end

  def hardware_ship_scope
    ::Certification::Ship.available_for(current_user)
      .joins(:project)
      .where.not(projects: { hardware_stage: nil })
  end

  def hardware_funding_list_scope
    ::Certification::FundingRequest.for_reviewer(current_user)
      .joins(:project)
      .where.not(projects: { hardware_stage: nil })
  end

  def hardware_ship_list_scope
    ::Certification::Ship.for_reviewer(current_user)
      .joins(:project)
      .where.not(projects: { hardware_stage: nil })
  end

  def review_item(type, record, project, owner, submitted_at)
    {
      type: type,
      stage: type == :funding ? "design" : "build",
      stage_label: type == :funding ? "Design" : "Build",
      record: record,
      project: project,
      owner: owner,
      submitted_at: submitted_at,
      token: "#{type}:#{record.id}"
    }
  end

  def reviewed_today_count
    ::Certification::FundingRequest.reviewed_today(current_user) +
      ::Certification::Ship.reviewed_today(current_user)
  end

  # Of the given project ids, those whose active mission is Hackpad — so the
  # queue can flag them with a pill without an N+1 of Project#current_mission
  # per row. Returns a Set for O(1) lookup in the view.
  def hackpad_project_ids(project_ids)
    return Set.new if project_ids.empty?

    Project::MissionAttachment.active
      .joins(:mission)
      .where(missions: { slug: "hackpad" }, project_id: project_ids)
      .pluck(:project_id)
      .to_set
  end

  def hardware_queue_stats
    funding_scope = hardware_funding_list_scope
    ship_scope = hardware_ship_list_scope
    funding_pending = funding_scope.pending.count
    ship_pending = ship_scope.pending.count
    funding_approved = funding_scope.approved.count
    funding_returned = funding_scope.returned.count
    ship_approved = ship_scope.approved.count
    ship_returned = ship_scope.returned.count
    approved_count = funding_approved + ship_approved
    returned_count = funding_returned + ship_returned
    decided_count = approved_count + returned_count
    oldest = [ funding_scope.pending.order(:created_at).first, ship_scope.pending.order(:created_at).first ]
      .compact
      .min_by(&:created_at)
    today = Time.current.beginning_of_day
    week = Time.current.beginning_of_week

    {
      pending: funding_pending + ship_pending,
      funding_pending: funding_pending,
      ship_pending: ship_pending,
      approved: approved_count,
      returned: returned_count,
      decided: decided_count,
      approval_rate: decided_count.zero? ? nil : (approved_count * 100.0 / decided_count).round,
      decisions_today: funding_scope.where.not(status: :pending).where(decided_at: today..).count +
        ship_scope.where.not(status: :pending).where(decided_at: today..).count,
      new_today: funding_scope.where(created_at: today..).count + ship_scope.where(created_at: today..).count,
      decisions_this_week: funding_scope.where.not(status: :pending).where(decided_at: week..).count +
        ship_scope.where.not(status: :pending).where(decided_at: week..).count,
      new_this_week: funding_scope.where(created_at: week..).count + ship_scope.where(created_at: week..).count,
      oldest_pending: oldest && review_item(oldest.is_a?(::Certification::FundingRequest) ? :funding : :ship, oldest, oldest.project, oldest.respond_to?(:owner) ? oldest.owner : nil, oldest.created_at),
      queue_target: ::Certification::Ship::QUEUE_TARGET,
      sla_days: ::Certification::Ship::SLA_DAYS,
      overdue_pending: funding_scope.pending.where("#{::Certification::FundingRequest.table_name}.created_at < ?", Time.current - ::Certification::FundingRequest::SLA_DAYS.days).count +
        ship_scope.pending.where("#{::Certification::Ship.table_name}.created_at < ?", Time.current - ::Certification::Ship::SLA_DAYS.days).count
    }
  end

  def apply_queue_filters(scope, model)
    scope = scope.where(status: @status) unless @status == "all"
    scope = scope.where("#{model.table_name}.created_at >= ?", @from.beginning_of_day) if @from
    scope = scope.where("#{model.table_name}.created_at <= ?", @to.end_of_day) if @to
    return scope if @search.blank?

    if @search.match?(/\A\d+\z/)
      scope.where("#{model.table_name}.id = :id OR projects.title ILIKE :q",
                  id: @search.to_i, q: "%#{@search}%")
    else
      scope.where("projects.title ILIKE ?", "%#{@search}%")
    end
  end

  def sort_review_items(items)
    sorted = items.sort_by { |item| item[:submitted_at] || Time.zone.at(0) }
    @sort == "newest" ? sorted.reverse : sorted
  end

  def hardware_leaderboard(period, now: Time.current, limit: 10)
    rows = Hash.new(0)
    [ ::Certification::FundingRequest, ::Certification::Ship ].each do |model|
      scope = model.joins(:reviewer)
        .where.not(reviewer_id: nil)
        .where.not(status: :pending)
        .where(project_id: Project.where.not(hardware_stage: nil))
      case period.to_sym
      when :daily then scope = scope.where(decided_at: now.beginning_of_day..)
      when :weekly then scope = scope.where(decided_at: now.beginning_of_week..)
      end
      scope.group("users.display_name").count.each do |name, count|
        rows[name] += count
      end
    end
    rows.sort_by { |name, count| [ -count, name ] }.first(limit).map { |name, count| { name: name, count: count } }
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_skip_tokens
    tokens = params[:skip].to_s.split(",").map(&:strip).reject(&:blank?).uniq
    {
      tokens: tokens,
      funding_ids: tokens.filter_map { |token| token.delete_prefix("funding:").to_i if token.start_with?("funding:") },
      ship_ids: tokens.filter_map { |token| token.delete_prefix("ship:").to_i if token.start_with?("ship:") }
    }
  end

  def next_candidate(skip)
    funding = hardware_funding_scope
    funding = funding.where.not(id: skip[:funding_ids]) if skip[:funding_ids].any?
    ship = hardware_ship_scope
    ship = ship.where.not(id: skip[:ship_ids]) if skip[:ship_ids].any?

    candidates = []
    if (request = funding.order(claim_order_sql(::Certification::FundingRequest), :created_at).first)
      candidates << review_item(:funding, request, request.project, request.owner, request.created_at)
    end
    if (ship_review = ship.order(claim_order_sql(::Certification::Ship), :created_at).first)
      candidates << review_item(:ship, ship_review, ship_review.project, ship_review.owner, ship_review.created_at)
    end

    candidates.min_by { |item| [ item[:record].reviewer_id == current_user.id ? 0 : 1, item[:submitted_at] ] }
  end

  def claim_candidate(candidate)
    case candidate[:type]
    when :funding
      ::Certification::FundingRequest.atomic_claim!(candidate[:record].id, current_user)
    when :ship
      ::Certification::Ship.atomic_claim!(candidate[:record].id, current_user)
    end
  end

  def claim_order_sql(model)
    Arel.sql(model.sanitize_sql_array([ "CASE WHEN reviewer_id = ? THEN 0 ELSE 1 END", current_user.id ]))
  end

  # Provider URLs expire after ~1h, so a short cache keyed by project kills the
  # per-render HTTP fan-out without staling them.
  RECORDINGS_CACHE_TTL = 1.minute

  def lapse_timelapses_for_review
    Rails.cache.fetch([ "hardware_review_recordings", "lapse", @project.id ], expires_in: RECORDINGS_CACHE_TTL) do
      LapseService.timelapses_for_project(
        hackatime_user_id: review_owner&.hackatime_identity&.uid,
        project_keys: @project.hackatime_keys
      )
    end
  end

  def lookout_recordings_for_review
    Rails.cache.fetch([ "hardware_review_recordings", "lookout", @project.id ], expires_in: RECORDINGS_CACHE_TTL) do
      LookoutService.recordings_for_project(@project)
    end
  end

  # The .app-layout wrapper reserves the sidebar gutter itself; this body class
  # zeroes the body's own sidebar margin so the two don't stack into a huge gap.
  def set_body_class
    @body_class = "app-layout-page"
  end
end
