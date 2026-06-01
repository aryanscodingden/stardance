# frozen_string_literal: true

require "ipaddr"
require "resolv"

# Guards outbound HTTP requests to user-supplied URLs against SSRF.
#
# Two steps approach that eliminates DNS rebinding (TOCTOU):
#  step - 1
#   - resolves the hostname, reject any private/linklocal/loopback IP
#  step - 2
#   - return verified ip so callers can pin the connection to it,
#   preventing a second DNS lookup from resolving to a different address
module SafeUrl
  ALLOWED_SCHEMES = %w[http https].freeze
  class Error < StandardError; end
  def self.resolve_and_verify!(url)
    uri = URI.parse(url.to_s)
    raise Error, "Scheme not allowed" unless ALLOWED_SCHEMES.include?(uri.scheme)
    raise Error, "Host is blank"     if uri.host.blank?
    addresses = Resolv.getaddresses(uri.host)
    raise Error, "Could not resolve host" if addresses.empty?
    safe_ip = addresses.find { |addr| public_ip?(addr) }
    raise Error, "Host resolves to a non-public IP" unless safe_ip
    safe_ip
  rescue URI::InvalidURIError, Resolv::ResolvError, ArgumentError => e
    raise Error, e.message
  end
  def self.safe_to_probe?(url)
    resolve_and_verify!(url)
    true
  rescue Error
    false
  end
  def self.safe_head(url, limit: 3, open_timeout: 10, read_timeout: 10)
    raise Error, "Too many redirects" if limit <= 0
    uri         = URI.parse(url.to_s)
    verified_ip = resolve_and_verify!(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr       = verified_ip
    http.use_ssl      = (uri.scheme == "https")
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout
    response = http.request_head(uri.request_uri)
    if response.is_a?(Net::HTTPRedirection) && response["location"]
      safe_head(response["location"], limit: limit - 1,
                open_timeout: open_timeout, read_timeout: read_timeout)
    else
      response
    end
  end
  def self.public_ip?(ip_string)
    ip = IPAddr.new(ip_string)
    return false if ip.loopback? || ip.private? || ip.link_local?
    return false if ip.ipv4? && (ip.to_i == 0 || ip.to_i >= IPAddr.new("224.0.0.0").to_i)
    return false if ip.ipv6? && (ip == IPAddr.new("::") || ip.ipv4_mapped?)
    true
  rescue IPAddr::InvalidAddressError
    false
  end
end
