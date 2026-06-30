module User::Streakable
  extend ActiveSupport::Concern

  included do
    has_many :streak_activities, dependent: :destroy
  end

  def streak_today_date
    StreakActivity.streak_date_for(Time.current, timezone)
  end

  def current_streak
    has_attribute?(:current_streak) ? super : 0
  end

  def recalculate_streak!
    return unless has_attribute?(:current_streak)
    update_column(:current_streak, calculate_current_streak)
  end

  def longest_streak
    @_longest_streak ||= begin
      dates = streak_activities.completed.order(:activity_date).pluck(:activity_date)
      return 0 if dates.empty?
      max = run = 1
      dates.each_cons(2) do |a, b|
        b == a + 1.day ? (run += 1) : (run = 1)
        max = run if run > max
      end
      max
    end
  end

  def streak_today_activity
    streak_activities.for_date(streak_today_date).first
  end

  # Most recent day (streak-day granularity) the user logged any Hackatime
  # coding time. Read straight from streak_activities, so no live Hackatime
  # call — nil if they've never logged time on a linked project.
  def last_hackatime_activity_on
    streak_activities.where("coded_seconds > 0").maximum(:activity_date)
  end

  def streak_week_activities
    today = streak_today_date
    week_start = today.beginning_of_week(:sunday)
    build_day_list(week_start, week_start + 6.days, today)
  end

  def streak_month_calendar(year, month)
    today = streak_today_date
    first = Date.new(year, month, 1)
    cal_start = first.beginning_of_week(:sunday)
    cal_end = first.end_of_month.end_of_week(:sunday)

    activities = streak_activities.for_range(cal_start..cal_end).index_by(&:activity_date)

    # +/- 1 day so streak bars connect across grid boundaries
    completed = streak_activities.completed
      .for_range((cal_start - 1.day)..(cal_end + 1.day))
      .pluck(:activity_date).to_set

    (cal_start..cal_end).map do |date|
      done = completed.include?(date)
      {
        date: date,
        in_month: date.month == month,
        coded_seconds: activities[date]&.coded_seconds || 0,
        completed: done,
        today: date == today,
        future: date > today,
        streak_left: done && completed.include?(date - 1.day) && date.wday != 0,
        streak_right: done && completed.include?(date + 1.day) && date.wday != 6
      }
    end
  end

  def streak_next_day_at
    tz = timezone.presence || "UTC"
    local = Time.current.in_time_zone(tz)
    boundary = local.change(hour: 2)
    (local < boundary ? boundary : boundary + 1.day).utc
  end

  private

  def calculate_current_streak
    today = streak_today_date
    dates = streak_activities.completed
      .where("activity_date <= ?", today)
      .order(activity_date: :desc)
      .limit(400)
      .pluck(:activity_date)
      .to_set
    date = dates.include?(today) ? today : today - 1.day
    count = 0
    count += 1 and date -= 1.day while dates.include?(date)
    count
  end

  def build_day_list(from, to, today)
    activities = streak_activities.for_range(from..to).index_by(&:activity_date)
    (from..to).map do |date|
      {
        date: date,
        day_letter: Date::ABBR_DAYNAMES[date.wday][0],
        coded_seconds: activities[date]&.coded_seconds || 0,
        completed: activities[date]&.completed? || false,
        today: date == today,
        future: date > today
      }
    end
  end
end
