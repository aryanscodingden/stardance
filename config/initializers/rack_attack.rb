require "rack/attack"

Rack::Attack.cache.store = Rails.cache

module RackAttackClient
  STATIC_PATHS = %r{\A/(assets|favicon\.ico|robots\.txt|manifest\.json|apple-touch-icon)}.freeze
  AUTH_PATHS = %r{\A/(auth/[^/]+/callback|oauth/callback|auth/failure)\z}.freeze

  def self.ip(request)
    request.get_header("HTTP_CF_CONNECTING_IP").presence || request.ip
  end

  def self.static_request?(request)
    request.path.match?(STATIC_PATHS)
  end

  def self.health_check?(request)
    request.path == "/up"
  end

  def self.auth_request?(request)
    request.path.match?(AUTH_PATHS)
  end
end

Rack::Attack.safelist("allow health checks") do |req|
  RackAttackClient.health_check?(req)
end

Rack::Attack.safelist("allow static assets") do |req|
  RackAttackClient.static_request?(req)
end

Rack::Attack.throttle("requests/ip", limit: 600, period: 5.minutes) do |req|
  RackAttackClient.ip(req)
end

Rack::Attack.throttle("request bursts/ip", limit: 120, period: 1.minute) do |req|
  RackAttackClient.ip(req)
end

Rack::Attack.throttle("state-changing requests/ip", limit: 60, period: 1.minute) do |req|
  RackAttackClient.ip(req) unless req.get? || req.head? || req.options?
end

Rack::Attack.throttle("auth callbacks/ip", limit: 20, period: 5.minutes) do |req|
  RackAttackClient.ip(req) if RackAttackClient.auth_request?(req)
end

Rack::Attack.throttled_responder = lambda do |req|
  match_data = req.env["rack.attack.match_data"] || {}
  retry_after = match_data.fetch(:period, 60).to_s

  body = {
    error: "rate_limited",
    message: "Too many requests. Please slow down."
  }.to_json

  [
    429,
    {
      "Content-Type" => "application/json",
      "Retry-After" => retry_after
    },
    [ body ]
  ]
end
