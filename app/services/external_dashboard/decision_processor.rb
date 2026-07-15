module ExternalDashboard
  class DecisionProcessor
    DECISION_EVENT = "certification.decision".freeze
    TEST_EVENT = "test".freeze
    EXTERNAL_ID_PATTERN = /\A\d{1,32}\z/
    COMMENT_MAX_LENGTH = 10_000
    REPLAY_CLOCK_SKEW = 5.minutes

    Result = Struct.new(:status, :body, keyword_init: true)

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = (payload || {}).with_indifferent_access
    end

    def call
      return ok(event: TEST_EVENT, received: true) if event == TEST_EVENT
      return error(:bad_request, "unsupported event: #{event.inspect}") unless event == DECISION_EVENT
      return error(:bad_request, "missing certification object") unless certification.is_a?(Hash)
      return error(:unprocessable_entity, "unsupported status: #{decision_status.inspect}") unless Certification::Ship::EXTERNAL_DECISION_MAP.key?(decision_status)

      cert = find_cert
      return error(:not_found, "cert not found (externalId=#{certification[:externalId].inspect} id=#{certification[:id].inspect})") if cert.nil?
      return ignored("project is deleted") if cert.project.nil? || cert.project.deleted_at.present?
      return ignored("project owner is banned") if cert.owner&.banned?
      return error(:bad_request, "missing or invalid timestamp") if decision_timestamp.nil?
      return error(:conflict, "decision predates this review cycle (timestamp=#{payload[:timestamp].inspect})") if cert.pending? && stale_decision?(cert)

      if proof_video_url
        return error(:bad_request, "proofVideoUrl must be an http(s) URL") unless proof_video_url.match?(Certification::Ship::PROOF_VIDEO_URL_PATTERN)
        return error(:bad_request, "proofVideoUrl exceeds #{Certification::Ship::PROOF_VIDEO_URL_MAX_LENGTH} chars") if proof_video_url.length > Certification::Ship::PROOF_VIDEO_URL_MAX_LENGTH
      end

      apply(cert)
    end

    private

    attr_reader :payload

    def apply(cert)
      target_status = Certification::Ship::EXTERNAL_DECISION_MAP.fetch(decision_status)

      PaperTrail.request(whodunnit: whodunnit) do
        cert.with_lock do
          if cert.pending?
            apply_decision!(cert, target_status)
            ok(decision_payload(cert, idempotent: false))
          elsif cert.status.to_sym == target_status
            cert.assign_external_certification_id!(certification[:id])
            ok(decision_payload(cert, idempotent: true))
          else
            error(:conflict, "cert #{cert.id} is already #{cert.status} locally — refusing to apply remote #{decision_status}")
          end
        end
      end
    end

    def event
      payload[:event].to_s
    end

    def certification
      payload[:certification]
    end

    def decision_status
      certification[:status].to_s
    end

    def find_cert
      uuid = certification[:id].to_s
      if uuid.match?(Certification::Ship::EXTERNAL_CERTIFICATION_ID_PATTERN)
        by_uuid = Certification::Ship.find_by(external_certification_id: uuid)
        return by_uuid if by_uuid
      end

      cert_id = parse_cert_id
      cert_id && Certification::Ship.find_by(id: cert_id)
    end

    def parse_cert_id
      raw = certification[:externalId].to_s
      raw.match?(EXTERNAL_ID_PATTERN) ? raw.to_i : nil
    end

    def reviewer
      return @reviewer if defined?(@reviewer)
      slack_id = certification[:reviewerSlackId].to_s.presence
      user = slack_id && User.find_by(slack_id: slack_id)
      @reviewer = (user && !user.banned? && user.can_review?) ? user : nil
    end

    def decision_timestamp
      return @decision_timestamp if defined?(@decision_timestamp)
      @decision_timestamp = begin
        Time.iso8601(payload[:timestamp].to_s)
      rescue ArgumentError
        nil
      end
    end

    def stale_decision?(cert)
      decision_timestamp.present? && decision_timestamp < (cert.created_at - REPLAY_CLOCK_SKEW)
    end

    def whodunnit
      reviewer&.id&.to_s || "external_dashboard"
    end

    def reviewer_comment
      certification[:reviewerComment].to_s.presence&.truncate(COMMENT_MAX_LENGTH, omission: "")
    end

    def proof_video_url
      certification[:proofVideoUrl].to_s.presence
    end

    def apply_decision!(cert, target_status)
      cert.update!(status: target_status, feedback: reviewer_comment, reviewer_id: reviewer&.id, proof_video_url: proof_video_url)
      cert.assign_external_certification_id!(certification[:id])
    end

    def decision_payload(cert, idempotent:)
      {
        idempotent: idempotent,
        ship_review: { id: cert.id, status: cert.status, project_id: cert.project_id, external_certification_id: cert.external_certification_id }
      }
    end

    def ok(body)
      Result.new(status: :ok, body: body)
    end

    def ignored(reason)
      Rails.logger.warn "[ExternalDashboard::DecisionProcessor] ignored decision: #{reason}"
      Result.new(status: :ok, body: { ignored: reason })
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::DecisionProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end
  end
end
