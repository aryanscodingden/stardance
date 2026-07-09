module ExternalDashboard
  class ShipWebhookService
    INGEST_PATH = "/api/v1/certifications/ingest".freeze

    Result = Struct.new(:status, :cert_id, :http_status, :error, keyword_init: true)

    def self.call(cert, require_complete_fields: false)
      new(cert, require_complete_fields: require_complete_fields).call
    end

    def initialize(cert, require_complete_fields: false)
      @cert = cert
      @require_complete_fields = require_complete_fields
    end

    def call
      return Result.new(status: :not_configured, error: Client::NOT_CONFIGURED_ERROR) unless Client.configured?
      return Result.new(status: :skipped, error: "cert has no project") if project.nil?
      return Result.new(status: :skipped, error: "hardware project — out of scope") if project.hardware?
      return Result.new(status: :skipped, error: "cert has no ship_event") if ship_event.nil?
      return Result.new(status: :skipped, error: "owner has no slack_id") if owner_slack_id.blank?
      if @require_complete_fields && missing_required_fields.any?
        return Result.new(status: :skipped, error: "missing required fields: #{missing_required_fields.join(', ')}")
      end

      response = Client.connection.post(INGEST_PATH, payload.to_json)
      parse_response(response)
    end

    private

    attr_reader :cert

    def missing_required_fields
      @missing_required_fields ||= {
        "projectName" => project.title,
        "description" => project.description,
        "demo" => project.demo_url,
        "repo" => project.repo_url,
        "readme" => project.readme_url,
        "username" => cert.owner&.display_name
      }.select { |_field, value| value.blank? }.keys
    end

    def project
      @project ||= cert.project
    end

    def ship_event
      @ship_event ||= cert.verdict_ship_event
    end

    def owner_slack_id
      cert.owner&.slack_id.presence
    end

    def payload
      base_payload.merge(cert.pending? ? pending_payload : decision_payload).compact
    end

    def pending_payload
      {
        status: "pending",
        createdAt: cert.created_at&.iso8601
      }
    end

    def base_payload
      {
        id: cert.id.to_s,
        projectName: project.title,
        projectType: "Software",
        shipType: ship_type,
        description: project.description.presence,
        aiDeclaration: project.ai_declaration.presence,
        updatedProject: project.update_description.presence,
        submittedBy: submitted_by.presence,
        links: links.presence,
        metadata: { devTime: dev_time_seconds }
      }
    end

    def decision_payload
      {
        status: cert.approved? ? "approved" : "rejected",
        feedback: cert.feedback.presence,
        proofVideoUrl: cert.proof_video_url.presence,
        reviewerSlackId: cert.reviewer&.slack_id.presence,
        createdAt: cert.created_at&.iso8601,
        decidedAt: cert.decided_at&.iso8601
      }
    end

    def ship_type
      project.ship_reviews.where("id < ?", cert.id).exists? ? "recertification" : "initial"
    end

    def submitted_by
      {
        slackId: owner_slack_id,
        username: cert.owner&.display_name.presence
      }.compact
    end

    def links
      {
        demo: project.demo_url.presence,
        repo: project.repo_url.presence,
        readme: project.readme_url.presence
      }.compact
    end

    def dev_time_seconds
      ((ship_event.hours_at_ship || 0) * 3600).to_i
    end

    def parse_response(response)
      body = Client.parse_json(response.body)
      cert_id = body["certId"]

      case response.status
      when 200..299
        Result.new(status: :ok, cert_id: cert_id, http_status: response.status)
      when 409
        Result.new(status: :duplicate, cert_id: cert_id, http_status: response.status)
      when 400..499
        Result.new(status: :client_error, http_status: response.status, error: Client.error_from(body))
      else
        Result.new(status: :server_error, http_status: response.status, error: Client.error_from(body))
      end
    end
  end
end
