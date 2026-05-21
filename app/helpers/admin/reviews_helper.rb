module Admin::ReviewsHelper
  # Parse repo_url to extract platform and username information
  # Returns a hash with :platform, :platform_name, :username, and :icon
  # Example: { platform: "github", platform_name: "GitHub", username: "hackclub", icon: "github" }
  def parse_repo_info(repo_url)
    return nil if repo_url.blank?

    begin
      uri = URI.parse(repo_url)
    rescue URI::InvalidURIError
      return nil
    end

    return nil unless uri.host

    host = uri.host.downcase
    path = uri.path

    # Remove leading slash and split path
    path_parts = path.sub(/^\//, "").split("/")
    return nil if path_parts.empty?

    username = path_parts.first

    # Detect platform based on host
    platform_info = case host
    when /github\.com$/
      { platform: "github", platform_name: "GitHub", icon: "github" }
    when /gitlab\.com$/
      { platform: "gitlab", platform_name: "GitLab", icon: "gitlab" }
    when /codeberg\.org$/
      { platform: "codeberg", platform_name: "Codeberg", icon: "codeberg" }
    when /bitbucket\.org$/
      { platform: "bitbucket", platform_name: "Bitbucket", icon: "bitbucket" }
    when /sr\.ht$/, /git\.sr\.ht$/
      { platform: "sourcehut", platform_name: "SourceHut", icon: "sourcehut" }
    else
      # Generic git hosting
      { platform: "git", platform_name: host, icon: "git" }
    end

    platform_info.merge(username: username)
  end

  # Fetch platform contribution stats for a user
  # Returns formatted string for display or nil if unavailable
  # Example: "31 contributions" or "org repo"
  def fetch_platform_contributions(platform, username)
    return nil if platform.blank? || username.blank?

    result = Admin::ReviewPlatformService.fetch_contributions(platform, username)

    if result[:error]
      case result[:error]
      when :org_repo
        "org repo"
      else
        nil # Hide count for other errors (timeout, unsupported, etc.)
      end
    elsif result[:total]
      pluralize(result[:total], "contribution")
    else
      nil
    end
  end

  # Fetch raw contribution count for a user
  # Returns integer count or nil if unavailable
  def fetch_contribution_count(platform, username)
    return nil if platform.blank? || username.blank?

    result = Admin::ReviewPlatformService.fetch_contributions(platform, username)

    if result[:error]
      nil
    elsif result[:total]
      result[:total]
    else
      nil
    end
  end

  # Fetch full platform contribution data for calendar visualization
  # Returns hash with :contributions array and :total, or nil if unavailable
  # Example: { contributions: [{date: "2024-01-01", count: 5}, ...], total: 365 }
  def fetch_platform_contribution_data(platform, username)
    return nil if platform.blank? || username.blank?

    result = Admin::ReviewPlatformService.fetch_contributions(platform, username)

    if result[:error]
      nil # Hide data for errors
    elsif result[:contributions] && result[:total]
      {
        contributions: result[:contributions],
        total: result[:total]
      }
    else
      nil
    end
  end

  # Prepare calendar data for GitHub-style contribution visualization
  # Returns array of day objects with date, count, and level for the last 365 days
  # Example: [{ date: "2024-01-01", count: 5, level: 1, day_of_week: 1, week_index: 0 }, ...]
  def prepare_contribution_calendar_data(platform, username)
    return nil if platform.blank? || username.blank?

    result = Admin::ReviewPlatformService.fetch_contributions(platform, username)
    return nil if result[:error] || result[:contributions].blank?

    # Create a hash map of contributions by date for quick lookup
    contribution_map = result[:contributions].each_with_object({}) do |day, hash|
      hash[day["date"]] = day["count"]
    end

    # Calculate date range (last 365 days)
    today = Date.current
    one_year_ago = today - 364 # 365 days including today

    # Normalize to start on Sunday for first week
    start_date = one_year_ago - one_year_ago.wday

    # Generate all days for the calendar grid
    days = []
    current_date = start_date
    week_index = 0
    day_index = 0

    # Continue until we've covered all days through today
    while current_date <= today || day_index % 7 != 0
      date_str = current_date.to_s
      count = contribution_map[date_str] || 0
      day_of_week = current_date.wday # 0 = Sunday, 6 = Saturday

      # Only include days within our actual range (one_year_ago to today)
      if current_date >= one_year_ago && current_date <= today
        days << {
          date: date_str,
          count: count,
          level: calculate_contribution_level(count),
          day_of_week: day_of_week,
          week_index: week_index
        }
      elsif current_date > today
        # Add empty cells to complete the final week
        days << {
          date: date_str,
          count: 0,
          level: 0,
          day_of_week: day_of_week,
          week_index: week_index,
          future: true # Mark as future date (outside range)
        }
      end

      # Move to next day
      current_date += 1
      day_index += 1

      # Increment week index every 7 days
      week_index = day_index / 7
    end

    days
  end

  # Generate profile URL for a user on their git hosting platform
  # Returns the full URL to the user's profile
  def platform_profile_url(platform, username)
    return nil if platform.blank? || username.blank?

    case platform
    when "github"
      "https://github.com/#{username}"
    when "gitlab"
      "https://gitlab.com/#{username}"
    when "codeberg"
      "https://codeberg.org/#{username}"
    when "bitbucket"
      "https://bitbucket.org/#{username}"
    when "sourcehut"
      "https://sr.ht/~#{username}"
    else
      nil # Can't generate URL for unknown platforms
    end
  end

  # Determine skill level based on contribution count
  # Returns hash with :label and :class for styling
  # 0-499: Beginner, 500-999: Intermediate, 1000+: Advanced
  def contribution_skill_level(contribution_count)
    return nil if contribution_count.nil?

    if contribution_count < 500
      { label: "Beginner", class: "level-beginner" }
    elsif contribution_count < 1000
      { label: "Intermediate", class: "level-intermediate" }
    else
      { label: "Advanced", class: "level-advanced" }
    end
  end

  private

  # Calculate contribution level based on count
  # 0 contributions = 0, <10 = 1, <20 = 2, <25 = 3, <30 = 4, >=30 = 5
  def calculate_contribution_level(count)
    return 0 if count == 0
    return 1 if count < 10
    return 2 if count < 20
    return 3 if count < 25
    return 4 if count < 30
    5 # 30 or more
  end
end
