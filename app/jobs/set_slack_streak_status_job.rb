class SetSlackStreakStatusJob < ApplicationJob
  queue_as :latency_5m
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: 30.seconds, attempts: 3

  def perform(user_id, previous_streak: nil)
    user = User.find_by(id: user_id)
    return unless user
    return unless user.slack_id.present?
    return unless streak_status_enabled?(user)

    streak = user.current_streak
    return if previous_streak && streak == previous_streak

    tier = streak_tier(streak)

    if tier
      set_status(user.slack_id, "#{streak} day streak on stardance!", ":stardance-streak-#{tier}d:")
    else
      set_status(user.slack_id, "", "")
    end
  end

  private

  def set_status(slack_id, text, emoji)
    Rails.cache.write("streak_status_set:#{slack_id}", true, expires_in: 30.seconds)
    client = Slack::Web::Client.new(token: slack_admin_token)
    client.users_profile_set(
      user: slack_id,
      profile: { status_text: text, status_emoji: emoji, status_expiration: 0 }.to_json
    )
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error("Failed to set streak status for #{slack_id}: #{e.message}")
  end

  STREAK_TIERS = [ 10, 7, 5, 3, 1 ].freeze

  def streak_tier(count)
    tier = STREAK_TIERS.find { |t| count >= t }
    tier&.to_s
  end

  def streak_status_enabled?(user)
    return true unless user.preference&.has_attribute?(:streak_slack_status_enabled)
    user.preference&.streak_slack_status_enabled?
  end

  def slack_admin_token
    Rails.application.credentials.dig(:slack, :admin_token) || ENV["SLACK_ADMIN_TOKEN"]
  end
end
