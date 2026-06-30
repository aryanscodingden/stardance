module Api
  module Slack
    class EventsController < ActionController::API
      before_action :verify_slack_signature

      def create
        case params[:type]
        when "url_verification"
          render json: { challenge: params[:challenge] }
        when "event_callback"
          handle_event(params[:event])
          head :ok
        else
          head :ok
        end
      end

      private

      def handle_event(event)
        return unless event

        case event[:type]
        when "user_change"
          user = event[:user]
          return unless user

          status_emoji = user.dig(:profile, :status_emoji).to_s
          return unless status_emoji.include?("stardance-streak-")

          slack_id = user[:id]
          return if Rails.cache.exist?("streak_status_set:#{slack_id}")

          StreakSlackClownJob.perform_later(slack_id, status_emoji)
        end
      end

      def verify_slack_signature
        signing_secret = Rails.application.credentials.dig(:slack, :signing_secret) || ENV["SLACK_SIGNING_SECRET"]
        unless signing_secret
          Rails.logger.warn("Slack signing secret not configured, skipping verification")
          return
        end

        timestamp = request.headers["X-Slack-Request-Timestamp"]
        return head :unauthorized if timestamp.blank?
        return head :unauthorized if (Time.now.to_i - timestamp.to_i).abs > 300

        body = request.raw_post
        sig_basestring = "v0:#{timestamp}:#{body}"
        computed = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)}"
        signature = request.headers["X-Slack-Signature"]

        unless ActiveSupport::SecurityUtils.secure_compare(computed, signature.to_s)
          head :unauthorized
          throw(:abort)
        end
      end
    end
  end
end
