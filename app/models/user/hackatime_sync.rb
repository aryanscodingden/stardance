module User::HackatimeSync
  extend ActiveSupport::Concern

  def all_time_coding_seconds
    try_sync_hackatime_data!&.dig(:projects)&.values&.sum || 0
  end

  def hackatime_token_stale?
    identity = hackatime_identity
    return false if identity&.access_token.blank?

    sync = try_sync_hackatime_data!
    return false unless sync

    sync[:token_stale] || Rails.cache.read("hackatime_api_key:#{identity.uid}").nil?
  end

  def has_logged_one_hour?
    all_time_coding_seconds >= 3600
  end

  # Title of the Stardance project to feature for this user: the project that
  # has logged the most Hackatime time (summed across all the Hackatime projects
  # linked to it), falling back to an arbitrary project of theirs when none have
  # any time yet. The fallback is stable (oldest project) rather than truly
  # random so it doesn't churn every sync and re-push to Loops; swap the
  # `order(:id).first` for `order("RANDOM()").first` if you want it randomized.
  # Reuses the memoized stats fetch, so no extra Hackatime call.
  def most_active_project_title
    seconds_by_name = try_sync_hackatime_data!&.dig(:projects) || {}

    totals = Hash.new(0)
    User::HackatimeProject.where(user_id: id).where.not(project_id: nil).each do |hp|
      totals[hp.project_id] += seconds_by_name[hp.name].to_i
    end

    project_id, top_seconds = totals.max_by { |_id, seconds| seconds }
    project = top_seconds.to_i.positive? ? projects.find_by(id: project_id) : projects.order(:id).first
    project&.title
  end

  def try_sync_hackatime_data!(force: false)
    return @hackatime_data if @hackatime_data && !force
    return nil unless hackatime_identity

    result = HackatimeService.fetch_stats(hackatime_identity.uid, access_token: hackatime_identity.access_token)
    return nil unless result

    if result[:banned] && !banned?
      Rails.logger.warn "User #{id} (#{slack_id}) is banned on Hackatime, auto-banning"
      ban!(reason: "Automatically banned: User is banned on Hackatime")
    end

    if result[:projects].any?
      User::HackatimeProject.insert_all(
        result[:projects].keys.map { |name| { user_id: id, name: name } },
        unique_by: [ :user_id, :name ]
      )
    end

    @hackatime_data = result
  end

  # Overrides the association reader so forms show the latest synced projects
  # with zero-second entries filtered out.
  def hackatime_projects
    projects = super
    synced_data = try_sync_hackatime_data!
    return projects unless synced_data

    project_times = synced_data[:projects] || {}
    project_names_with_time = project_times.select { |_name, seconds| seconds.to_i > 0 }.keys
    return projects.none if project_names_with_time.empty?

    projects.where(name: project_names_with_time)
  end
end
