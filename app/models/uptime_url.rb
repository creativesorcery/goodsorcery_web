# A monitor URL, parsed and normalised (docs/ARCHITECTURE.md §12.5). Used by
# UptimeMonitor validation and by UptimeProbe for every redirect hop.
#
#   UptimeUrl.parse(" https://Example.com/up#top ")  # => URI "https://example.com/up"
#   UptimeUrl.new("http://10.0.0.1/").public?        # => false
#
# Only http and https, a host, no userinfo and at most MAX_LENGTH characters.
# #public? refuses localhost and blocked IP literals early, for a friendly
# validation error; the real guard is UptimeProbe::AddressGuard at resolve time.
# URLs may carry secrets in their query: never log or raise with them.
class UptimeUrl
  MAX_LENGTH = 2_048
  SCHEMES = %w[http https].freeze
  # Well-known ports of non-web services (FTP, SSH, Telnet, mail, SMB, SQL
  # Server, Oracle, Docker, MySQL, RDP, Postgres, AMQP, VNC, Redis,
  # Elasticsearch, Memcached, MongoDB). The hosted service refuses them, so
  # its probes can't be pointed at other people's non-web servers;
  # self-hosted installs may monitor any port.
  SERVICE_PORTS = Set[21, 22, 23, 25, 110, 143, 445, 465, 587, 993, 995, 1433, 1521, 2375, 2376,
                      3306, 3389, 5432, 5672, 5900, 6379, 9200, 11211, 27017].freeze

  def self.parse(string) = new(string).uri

  def self.port_allowed?(port, hosted: Rails.configuration.x.hosted)
    !hosted || !SERVICE_PORTS.include?(port)
  end

  # The normalised string when it parses, else the input stripped (for validation).
  def self.normalize(string) = parse(string)&.to_s || string.to_s.strip

  attr_reader :uri

  def initialize(string)
    @uri = build(string.to_s.strip)
  end

  def valid? = !uri.nil?

  def host = uri&.host

  def public?
    valid? && !UptimeProbe::AddressGuard.refused_literal?(uri.hostname)
  end

  def allowed_port? = valid? && self.class.port_allowed?(uri.port)

  private
    def build(string)
      return if string.empty? || string.length > MAX_LENGTH

      uri = URI.parse(string)
      normalized(uri) if acceptable?(uri)
    rescue URI::Error
      nil
    end

    def acceptable?(uri)
      SCHEMES.include?(uri.scheme&.downcase) && uri.host.present? && uri.userinfo.nil?
    end

    def normalized(uri)
      uri.scheme = uri.scheme.downcase
      uri.host = uri.host.downcase
      uri.fragment = nil
      uri.path = "/" if uri.path.empty?
      uri
    end
end
