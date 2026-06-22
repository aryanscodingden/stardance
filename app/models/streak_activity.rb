# == Schema Information
#
# Table name: streak_activities
#
#  id            :bigint           not null, primary key
#  activity_date :date             not null
#  coded_seconds :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_streak_activities_on_user_id                    (user_id)
#  index_streak_activities_on_user_id_and_activity_date  (user_id,activity_date) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class StreakActivity < ApplicationRecord
  DAILY_GOAL_SECONDS = 300 # 5 minutes

  belongs_to :user

  validates :activity_date, presence: true
  validates :activity_date, uniqueness: { scope: :user_id }
  validates :coded_seconds, numericality: { greater_than_or_equal_to: 0 }

  scope :completed, -> { where("coded_seconds >= ?", DAILY_GOAL_SECONDS) }
  scope :for_date, ->(date) { where(activity_date: date) }
  scope :for_range, ->(range) { where(activity_date: range) }

  has_paper_trail

  def completed?
    coded_seconds >= DAILY_GOAL_SECONDS
  end

  class << self
    def sync_for_user!(user)
      return nil unless user.hackatime_identity.present?

      linked_projects = user.hackatime_projects.where.not(project_id: nil)
      return nil if linked_projects.empty?

      project_keys = linked_projects.pluck(:name)
      today = streak_date_for(Time.current, user.timezone)

      seconds = HackatimeService.fetch_total_seconds_for_projects(
        user.hackatime_identity.uid,
        project_keys,
        start_date: today.to_s,
        end_date: (today + 1.day).to_s,
        access_token: user.hackatime_identity.access_token
      )
      return nil if seconds.nil?

      record = find_or_initialize_by(user_id: user.id, activity_date: today)
      record.update!(coded_seconds: seconds)
      record
    end

    def streak_date_for(time, timezone)
      tz = timezone.presence || "UTC"
      (time.in_time_zone(tz) - 2.hours).to_date
    end
  end
end
