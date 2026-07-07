module ExternalDashboard
  class ShipBackfillService
    DEFAULT_RATE_PER_SECOND = 2

    Result = Struct.new(:status, :enqueued, :error, keyword_init: true)

    def self.call(scope: nil, rate_per_second: DEFAULT_RATE_PER_SECOND)
      return Result.new(status: :not_configured, enqueued: 0, error: Client::NOT_CONFIGURED_ERROR) unless Client.configured?

      active_returns = Certification::Ship.pending.where.not(returned_by_id: nil)
      scope ||= Certification::Ship.where(external_certification_id: nil).where.not(id: active_returns.select(:id))
      link_ship_events(scope)
      cert_ids = scope.pluck(:id)
      cert_ids.each_with_index do |cert_id, index|
        delay = (index.to_f / rate_per_second).seconds
        ExternalDashboard::ShipWebhookJob.set(wait: delay).perform_later(cert_id)
      end

      return_ids = active_returns.where.not(external_certification_id: nil).pluck(:id)
      return_ids.each { |cert_id| ExternalDashboard::CertReturnJob.perform_later(cert_id) }

      Rails.logger.info "[ExternalDashboard::ShipBackfillService] enqueued=#{cert_ids.size} returns=#{return_ids.size} rate=#{rate_per_second}/s"
      Result.new(status: :ok, enqueued: cert_ids.size + return_ids.size)
    end

    def self.link_ship_events(scope)
      linked = 0
      scope.where(post_ship_event_id: nil).find_each do |cert|
        event = cert.project&.ship_events
                    &.where(post_ship_events: { created_at: ..cert.created_at })
                    &.order("post_ship_events.created_at DESC")
                    &.first
        next unless event

        cert.update!(post_ship_event_id: event.id)
        linked += 1
      end
      Rails.logger.info "[ExternalDashboard::ShipBackfillService] linked=#{linked} ship events" if linked.positive?
    end
  end
end
