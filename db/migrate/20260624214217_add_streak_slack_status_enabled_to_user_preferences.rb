class AddStreakSlackStatusEnabledToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :streak_slack_status_enabled, :boolean, default: true, null: false
  end
end
