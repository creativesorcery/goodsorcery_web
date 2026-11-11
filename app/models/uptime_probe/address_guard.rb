require "ipaddr"

# SSRF guard for uptime checks (docs/ARCHITECTURE.md §12.5). Resolves a host
# once and returns one vetted address for the probe to connect to (pinning,
# so DNS rebinding can't swap in another address). A host is refused when ANY
# of its addresses is blocked, so mixed public and private answers fail too.
#
#   guard = UptimeProbe::AddressGuard.new
#   guard.vet("example.com", timeout: 5)   # => IPAddr, or raises BlockedAddress / DnsFailure
#
# allow_private (GOODSORCERY_UPTIME_ALLOW_PRIVATE_ADDRESSES, never in
# production) turns the guard off for local testing. Tests pass allowed_ips
# to reach exactly a local test server, and resolver: (host, timeout -> [IPAddr]).
class UptimeProbe::AddressGuard
  BLOCKED_IPV4 = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
    192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 255.255.255.255/32
  ].map { |range| IPAddr.new(range) }.freeze

  # Also blocked outright: local-use NAT64 64:ff9b:1::/48 (RFC 8215; its IPv4
  # sits in prefix-length-dependent bits, so it can't be unwrapped safely),
  # Teredo 2001::/32 (relayed to an IPv4 we never vet) and ORCHIDv2 2001:20::/28.
  BLOCKED_IPV6 = %w[
    ::/128 ::1/128 fc00::/7 fe80::/10 fec0::/10 ff00::/8 100::/64 2001:db8::/32
    64:ff9b:1::/48 2001::/32 2001:20::/28
  ].map { |range| IPAddr.new(range) }.freeze

  # IPv6 ranges that carry an IPv4 address, with the bits to its right.
  EMBEDDED_IPV4 = {
    IPAddr.new("::ffff:0:0/96") => 0, # IPv4-mapped
    IPAddr.new("64:ff9b::/96") => 0,  # NAT64
    IPAddr.new("::/96") => 0,         # IPv4-compatible
    IPAddr.new("2002::/16") => 80     # 6to4: 2002:AABB:CCDD::/48
  }.freeze

  RESOLVER = lambda do |hostname, timeout|
    Addrinfo.getaddrinfo(hostname, nil, nil, :STREAM, timeout:).map { |info| IPAddr.new(info.ip_address.split("%").first) }.uniq
  end

  class << self
    def blocked_address?(ip)
      return BLOCKED_IPV4.any? { |range| range.include?(ip) } if ip.ipv4?

      BLOCKED_IPV6.any? { |range| range.include?(ip) } || embedded_ipv4(ip)&.then { |v4| blocked_address?(v4) } || false
    end

    # For UptimeUrl#public?: localhost names and blocked IP literals.
    def refused_literal?(hostname)
      return true if localhost?(hostname)

      ip = ip_literal(hostname)
      ip.present? && blocked_address?(ip)
    end

    def localhost?(hostname)
      name = hostname.to_s.downcase.chomp(".")
      name == "localhost" || name.end_with?(".localhost")
    end

    def ip_literal(hostname)
      IPAddr.new(hostname.to_s.delete_prefix("[").delete_suffix("]"))
    rescue IPAddr::Error
      nil
    end

    private
      def embedded_ipv4(ip)
        range, shift = EMBEDDED_IPV4.find { |candidate, _| candidate.include?(ip) }
        IPAddr.new((ip.to_i >> shift) & 0xFFFF_FFFF, Socket::AF_INET) if range
      end
  end

  def initialize(allow_private: Rails.configuration.x.uptime.allow_private_addresses, allowed_ips: [], resolver: RESOLVER)
    @allow_private = allow_private
    @allowed_ips = allowed_ips.map { |ip| IPAddr.new(ip.to_s) }
    @resolver = resolver
  end

  # The address to connect to. Raises UptimeProbe::BlockedAddress or
  # UptimeProbe::DnsFailure, never with the host name in the message.
  def vet(hostname, timeout:)
    raise UptimeProbe::BlockedAddress if self.class.localhost?(hostname) && !@allow_private

    addresses = resolve(hostname, timeout)
    raise UptimeProbe::DnsFailure if addresses.empty?
    raise UptimeProbe::BlockedAddress if addresses.any? { |ip| blocked?(ip) }

    addresses.first
  end

  def blocked?(ip)
    return false if @allow_private || @allowed_ips.include?(ip)

    self.class.blocked_address?(ip)
  end

  private
    def resolve(hostname, timeout)
      literal = self.class.ip_literal(hostname)
      literal ? [ literal ] : Array(@resolver.call(hostname, timeout))
    end
end
