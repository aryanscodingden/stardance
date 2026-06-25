# Talks to Lookout (Hack Club's screen-recording time tracker).
# See https://github.com/hackclub/lookout/blob/main/docs/integration.md
#
# Session creation is server-to-server (X-API-Key). Once a session exists, the
# browser drives recording against the token-authenticated client API, and we
# poll the same client API server-side to mirror status/duration/video back into
# our LookoutSession row. Lookout forwards the recording to Hackatime as a
# project named after `projectName`, which the user then links like any other
# Hackatime project.
class LookoutService
  BASE_URL = Rails.application.credentials.dig(:lookout, :base_url) || ENV.fetch("LOOKOUT_BASE_URL", "https://lookout.hackclub.com")
  API_KEY  = Rails.application.credentials.dig(:lookout, :api_key) || ENV.fetch("LOOKOUT_API_KEY", "")

  # Bounds for the review-page recording fetch (see recordings_for_project).
  REVIEW_OPEN_TIMEOUT = 3
  REVIEW_READ_TIMEOUT = 6
  MAX_REVIEW_RECORDINGS = 12

  class << self
    # Server-to-server. Returns the parsed body ({ token:, sessionId:,
    # sessionUrl: }) or nil on failure.
    def create_session(user_id:, project_id:, project_name:)
      response = internal_connection.post("api/internal/sessions") do |req|
        req.body = {
          metadata: {
            userId: user_id,
            projectId: project_id,
            projectName: project_name
          }
        }.to_json
      end

      if response.success?
        JSON.parse(response.body).symbolize_keys
      else
        Rails.logger.error "LookoutService create_session error: #{response.status} - #{response.body}"
        nil
      end
    rescue => e
      Rails.logger.error "LookoutService create_session exception: #{e.message}"
      nil
    end

    # Client API (token-authenticated). Status/duration/video for polling.
    def fetch_session(token)
      response = client_connection.get("api/sessions/#{token}")

      if response.success?
        JSON.parse(response.body).symbolize_keys
      else
        Rails.logger.error "LookoutService fetch_session error: #{response.status}"
        nil
      end
    rescue => e
      Rails.logger.error "LookoutService fetch_session exception: #{e.message}"
      nil
    end

    # Capture timestamps for a finished session, forwarded to Hackatime as
    # heartbeats. Returns the parsed body (an array, or a hash with a
    # "timestamps" key) or nil.
    def fetch_timings(token)
      response = client_connection.get("api/sessions/#{token}/timings")

      if response.success?
        JSON.parse(response.body)
      else
        Rails.logger.error "LookoutService fetch_timings error: #{response.status}"
        nil
      end
    rescue => e
      Rails.logger.error "LookoutService fetch_timings exception: #{e.message}"
      nil
    end

    def stop_session(token)
      response = client_connection.post("api/sessions/#{token}/stop")

      if response.success?
        JSON.parse(response.body).symbolize_keys
      else
        Rails.logger.error "LookoutService stop_session error: #{response.status}"
        nil
      end
    rescue => e
      Rails.logger.error "LookoutService stop_session exception: #{e.message}"
      nil
    end

    # The hosted recorder URL the browser opens to record a session. Derived
    # from the token so we don't need to persist sessionUrl.
    def session_url_for(token)
      "#{BASE_URL}/session?token=#{token}"
    end

    # A project's finished Lookout recordings, for the hardware funding review.
    # Lookout's stored video URLs are presigned and expire after ~1h, so we
    # refresh each session's video/thumbnail live (concurrently, bounded) at
    # render time. Returns an array of display hashes ({ video_url:,
    # thumbnail_url:, duration:, mode:, recorded_at: }) newest-first, or [] —
    # never raises, since the review page must render regardless.
    def recordings_for_project(project)
      sessions = project.lookout_sessions
                        .attachable
                        .order(Arel.sql("COALESCE(started_at, created_at) DESC"))
                        .limit(MAX_REVIEW_RECORDINGS)
                        .to_a
      return [] if sessions.empty?

      sessions.map { |session| Thread.new { review_recording(session) } }
              .map(&:value)
              .compact
    end

    private

    # Refresh one session's video/thumbnail from Lookout's client API, falling
    # back to the stored (possibly-expired) URL if the live call fails. Returns
    # a display hash, or nil when no playable video exists yet.
    def review_recording(session)
      remote = fetch_session_for_review(session.token)
      video = remote&.values_at(:videoUrl, :video_url, :recording_url)&.compact&.first
      video = session.recording_url if video.blank?
      return nil if video.blank?

      tracked = remote&.values_at(:trackedSeconds, :tracked_seconds)&.compact&.first
      {
        video_url: video,
        thumbnail_url: remote&.values_at(:thumbnailUrl, :thumbnail_url)&.compact&.first,
        duration: (tracked || session.duration_seconds).to_i,
        mode: session.mode,
        recorded_at: session.started_at || session.created_at
      }
    rescue => e
      # Runs inside a Thread whose value is re-raised in the request; an
      # unexpected remote shape must not 500 the review page.
      Rails.logger.error "LookoutService review_recording exception: #{e.message}"
      nil
    end

    # GET /api/sessions/:token on a short-timeout, per-call connection (so the
    # concurrent review fetches don't share one Faraday across threads).
    def fetch_session_for_review(token)
      response = review_connection.get("api/sessions/#{token}")
      return nil unless response.success?

      JSON.parse(response.body).symbolize_keys
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error "LookoutService review fetch timeout: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "LookoutService review fetch exception: #{e.message}"
      nil
    end

    def review_connection
      Faraday.new(url: BASE_URL) do |conn|
        conn.options.open_timeout = REVIEW_OPEN_TIMEOUT
        conn.options.timeout = REVIEW_READ_TIMEOUT
        conn.headers["Content-Type"] = "application/json"
        conn.adapter Faraday.default_adapter
      end
    end

    def internal_connection
      @internal_connection ||= Faraday.new(url: BASE_URL) do |conn|
        conn.headers["Content-Type"] = "application/json"
        conn.headers["X-API-Key"] = API_KEY
        conn.adapter Faraday.default_adapter
      end
    end

    def client_connection
      @client_connection ||= Faraday.new(url: BASE_URL) do |conn|
        conn.headers["Content-Type"] = "application/json"
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
