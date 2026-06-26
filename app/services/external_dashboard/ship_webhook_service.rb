module ExternalDashboard
  class ShipWebhookService
    INGEST_PATH = "/api/v1/certifications/ingest".freeze

    Result = Struct.new(:status, :cert_id, :http_status, :error, keyword_init: true) do
      def ok?       = status == :ok
      def duplicate? = status == :duplicate
    end

    def self.call(cert)
      new(cert).call
    end

    def initialize(cert)
      @cert = cert
    end

    def call
      return Result.new(status: :not_configured, error: "api key or workplace id missing") unless Client.configured?
      return Result.new(status: :skipped, error: "cert has no project") if project.nil?
      return Result.new(status: :skipped, error: "hardware project — out of scope") if project.hardware?
      return Result.new(status: :skipped, error: "cert has no ship_event") if ship_event.nil?
      return Result.new(status: :skipped, error: "owner has no slack_id") if owner_slack_id.blank?

      response = Client.connection.post(INGEST_PATH, payload.to_json)
      parse_response(response)
    end

    private

    attr_reader :cert

    def project
      @project ||= cert.project
    end

    def ship_event
      @ship_event ||= project&.last_ship_event
    end

    def owner
      @owner ||= project&.memberships&.owner&.order(:created_at)&.first&.user
    end

    def owner_slack_id
      owner&.slack_id.presence
    end

    def payload
      {
        id: "#{Client::EXTERNAL_ID_PREFIX}#{cert.id}",
        projectName: project&.title,
        projectType: project&.hardware? ? "Hardware" : "Software",
        shipType: ship_type,
        description: project&.description.presence,
        aiDeclaration: project&.ai_declaration.presence,
        updatedProjectDetails: project&.update_description.presence,
        submittedBy: submitted_by.presence,
        links: links.presence,
        metadata: { devTime: dev_time_seconds }
      }.compact
    end

    def ship_type
      project.ship_reviews.where.not(id: cert.id).exists? ? "recertification" : "initial"
    end

    def submitted_by
      {
        slackId: owner_slack_id,
        username: owner&.display_name.presence
      }.compact
    end

    def links
      {
        demo: project&.demo_url.presence,
        repo: project&.repo_url.presence,
        readme: project&.readme_url.presence
      }.compact
    end

    def dev_time_seconds
      ((ship_event&.hours_at_ship || 0) * 3600).to_i
    end

    def parse_response(response)
      body = parse_body(response.body)
      cert_id = body["certId"]
      error = body["error"].to_s.truncate(Client::ERROR_MESSAGE_MAX).presence

      case response.status
      when 200..299
        Result.new(status: :ok, cert_id: cert_id, http_status: response.status)
      when 409
        Result.new(status: :duplicate, cert_id: cert_id, http_status: response.status)
      when 400..499
        Result.new(status: :client_error, http_status: response.status, error: error)
      else
        Result.new(status: :server_error, http_status: response.status, error: error)
      end
    end

    def parse_body(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end
  end
end
