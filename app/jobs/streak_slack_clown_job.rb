class StreakSlackClownJob < ApplicationJob
  queue_as :latency_5m

  STREAK_EMOJI_PATTERN = /\Astardance-streak-(\d+)d\z/
  VALID_TIERS = [ 1, 3, 5, 7, 10 ].freeze

  def perform(slack_id, status_emoji)
    emoji_name = status_emoji.delete(":")
    match = emoji_name.match(STREAK_EMOJI_PATTERN)
    return unless match

    claimed_tier = match[1].to_i
    return unless VALID_TIERS.include?(claimed_tier)

    user = User.find_by(slack_id: slack_id)
    streak = user&.current_streak || 0
    expected_tier = VALID_TIERS.reverse.find { |t| streak >= t }
    return if expected_tier == claimed_tier

    set_clown_status(slack_id)
  end

  private

  def set_clown_status(slack_id)
    client = Slack::Web::Client.new(token: slack_admin_token)
    client.users_profile_set(
      user: slack_id,
      profile: {
        status_text: "this user really wanted a stardance streak",
        status_emoji: ":clown_face:",
        status_expiration: 0
      }.to_json
    )
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error("Failed to set clown status for #{slack_id}: #{e.message}")
  end

  def slack_admin_token
    Rails.application.credentials.dig(:slack, :admin_token) || ENV["SLACK_ADMIN_TOKEN"]
  end
end
