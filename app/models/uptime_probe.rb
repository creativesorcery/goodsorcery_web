require "net/http"

# One uptime check attempt: an HTTP(S) GET with an SSRF guard (docs/ARCHITECTURE.md §12.5).
#
#   UptimeProbe.new(monitor.url, monitor_id: monitor.id).check
#   # => Result(status: "up", response_time_ms: 212, http_status: 200, error_kind: nil)
#
# - Every hop (the URL and up to MAX_REDIRECTS redirects) is parsed by
#   UptimeUrl, resolved and vetted by AddressGuard, and connected to the vetted
#   address only (Net::HTTP#ipaddr=), while Host, SNI and certificate checks
#   keep the host name. The nil proxy argument ignores http_proxy from ENV.
# - TOTAL_TIMEOUT seconds per attempt, tracked by Deadline, with a hard
#   Timeout backstop around the network part (no DB, no locks inside).
# - At most MAX_BODY_BYTES of the body are read, then discarded, and at most
#   MAX_READ_BYTES per connection in all, headers included (Connection).
# - Never raises for network outcomes. Errors become an error kind; their
#   messages (which carry host names and URLs) are never logged or kept.
class UptimeProbe
  TOTAL_TIMEOUT = 10
  MAX_REDIRECTS = 3
  MAX_BODY_BYTES = 64.kilobytes
  # Status line, headers and 1xx responses plus MAX_BODY_BYTES of body and
  # one buffer of read-ahead, with room to spare.
  MAX_READ_BYTES = 128.kilobytes
  USER_AGENT = "GoodSorcery-Uptime/1.0".freeze

  class BlockedAddress < StandardError
    def initialize(message = "Address not allowed") = super
  end

  class DnsFailure < StandardError
    def initialize(message = "DNS lookup failed") = super
  end

  class ResponseTooLarge < StandardError
    def initialize(message = "Response exceeded the read cap") = super
  end

  Result = Data.define(:status, :response_time_ms, :http_status, :error_kind) do
    def self.up(response_time_ms:, http_status:) = new(status: "up", response_time_ms:, http_status:, error_kind: nil)

    def self.down(error_kind, response_time_ms: nil, http_status: nil)
      new(status: "down", response_time_ms:, http_status:, error_kind:)
    end

    def up? = status == "up"

    def down? = status == "down"
  end

  # The part of a final response a check keeps.
  Response = Data.define(:code, :location, :received_at)

  # Checked in order: IO::TimeoutError is an IOError, and SocketError covers resolution.
  ERROR_KINDS = {
    "timeout" => [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Deadline::Exceeded, Timeout::Error, IO::TimeoutError ],
    "dns_failure" => [ DnsFailure, SocketError ],
    "connection_refused" => [ Errno::ECONNREFUSED ],
    "tls_error" => [ OpenSSL::SSL::SSLError ],
    "blocked_address" => [ BlockedAddress ],
    "connection_error" => [ ResponseTooLarge, SystemCallError, EOFError, IOError, Net::HTTPBadResponse, Net::ProtocolError ]
  }.freeze

  def initialize(url, guard: AddressGuard.new, timeout: TOTAL_TIMEOUT, monitor_id: nil)
    @url = url
    @guard = guard
    @timeout = timeout
    @monitor_id = monitor_id
  end

  def check
    started_at = clock
    response = Timeout.timeout(@timeout + 1) { follow(first_uri, Deadline.new(@timeout)) }
    result_for(response, started_at)
  rescue StandardError => error
    Result.down(error_kind_for(error))
  end

  private
    def first_uri
      UptimeUrl.parse(@url) || raise(ArgumentError, "Unusable uptime URL")
    end

    def follow(uri, deadline)
      redirects = 0
      loop do
        response = fetch(uri, deadline)
        target = redirect_target(response, uri) if redirects < MAX_REDIRECTS
        return response unless target

        uri = target
        redirects += 1
      end
    end

    # A 3xx with a usable http(s) Location; anything else is the final response.
    def redirect_target(response, uri)
      return unless response.code.between?(300, 399) && response.location.present?

      UptimeUrl.parse(URI.join(uri.to_s, response.location).to_s)
    rescue URI::Error, ArgumentError
      nil
    end

    # Redirect hops and monitors saved before hosted mode was switched on
    # get the hosted port check too.
    def fetch(uri, deadline)
      raise BlockedAddress unless UptimeUrl.port_allowed?(uri.port)

      ip = @guard.vet(uri.hostname, timeout: deadline.remaining!)
      http = connection(uri, ip, deadline.remaining!)
      http.start { read_response(http, uri, deadline) }
    end

    # The TLS handshake runs under open_timeout. max_retries 0: Net::HTTP
    # would otherwise repeat a failed GET itself, outside the budget.
    def connection(uri, ip, seconds)
      Connection.new(uri.hostname, uri.port, nil).tap do |http|
        http.ipaddr = ip.to_s
        http.use_ssl = uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_hostname = true
        http.max_retries = 0
        http.open_timeout = http.read_timeout = http.write_timeout = seconds
      end
    end

    # Returns from inside the block, so Net::HTTP never reads the rest of the
    # body; leaving #start closes the connection.
    def read_response(http, uri, deadline)
      http.request(request_for(uri)) do |response|
        received_at = clock
        drain(response, deadline)
        return Response.new(code: response.code.to_i, location: response["location"], received_at:)
      end
    end

    def request_for(uri)
      Net::HTTP::Get.new(uri.request_uri, "User-Agent" => USER_AGENT, "Accept" => "*/*",
                         "Accept-Encoding" => "identity", "Connection" => "close")
    end

    def drain(response, deadline)
      read = 0
      response.read_body do |chunk|
        read += chunk.bytesize
        break if read >= MAX_BODY_BYTES

        deadline.remaining!
      end
    end

    def result_for(response, started_at)
      response_time_ms = ((response.received_at - started_at) * 1000).round
      return Result.up(response_time_ms:, http_status: response.code) if response.code.between?(200, 399)

      Result.down("http_status", response_time_ms:, http_status: response.code)
    end

    # Unexpected errors are logged by class name only: messages carry URLs.
    def error_kind_for(error)
      kind = ERROR_KINDS.find { |_, classes| classes.any? { |klass| error.is_a?(klass) } }&.first
      Rails.logger.warn("Uptime check #{@monitor_id} failed: #{error.class}") if kind.nil?
      kind || "connection_error"
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
