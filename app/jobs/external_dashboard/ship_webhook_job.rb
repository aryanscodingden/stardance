module ExternalDashboard
  class ShipWebhookJob < WebhookJob
    def perform(cert_id)
      cert = Certification::Ship.find(cert_id)
      fill_proof_video_url(cert)
      result = ExternalDashboard::ShipWebhookService.call(cert)

      case result.status
      when :ok, :duplicate
        cert.assign_external_certification_id!(result.cert_id)
        chain_pending_return(cert)
        verb = result.status == :duplicate ? "already ingested" : "ingested"
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} #{verb} external_cert_id=#{result.cert_id}"
      when :not_configured, :skipped
        level = cert.pending? ? :info : :warn
        Rails.logger.public_send(level, "[#{self.class.name}] cert=#{cert_id} skipped (#{result.error})")
      when :client_error
        log_remote_failure("client error", cert_id, result)
      when :server_error
        raise_server_error(cert_id, result)
      end
    end

    private

      def fill_proof_video_url(cert)
        return unless cert.proof_video_url.blank? && cert.verdict_video.attached?

        url_options = Rails.application.config.action_controller.default_url_options || {}
        return if url_options[:host].blank?

        url = Rails.application.routes.url_helpers.rails_blob_url(cert.verdict_video, **url_options)
        cert.update!(proof_video_url: url)
      rescue StandardError => e
        Rails.logger.warn "[#{self.class.name}] cert=#{cert.id} proof_video_url fill failed: #{e.class}: #{e.message}"
      end

      def chain_pending_return(cert)
        return unless cert.approved? && cert.external_certification_id.present?
        return if cert.post_ship_event_id.nil?

        project = cert.project
        return unless project

        active_return = project.ship_reviews.pending.where.not(returned_by_id: nil)
                               .find_by(post_ship_event_id: cert.post_ship_event_id)
        return unless active_return

        Certification::Ship.transaction do
          if cert.transfer_external_certification_id_to!(active_return)
            ExternalDashboard::CertReturnJob.perform_later(active_return.id)
          end
        end
      end
  end
end
