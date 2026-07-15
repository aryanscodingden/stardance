class ClearSlackStreakStatusJob < ApplicationJob
  queue_as :latency_5m

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user
    return unless user.slack_id.present?

    client = Slack::Web::Client.new(token: slack_admin_token)
    client.users_profile_set(
      user: user.slack_id,
      profile: { status_text: "", status_emoji: "", status_expiration: 0 }.to_json
    )
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error("Failed to clear streak status for #{user.slack_id}: #{e.message}")
  end

  private

  def slack_admin_token
    Rails.application.credentials.dig(:slack, :admin_token) || ENV["SLACK_ADMIN_TOKEN"]
  end
end
