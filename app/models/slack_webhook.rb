require "net/http"

# Posts one message to a Slack incoming webhook (docs/ARCHITECTURE.md §11.5).
#
#   SlackWebhook.new(connection.webhook_url).post(message.payload)
#   # => Result(outcome: :delivered, http_status: 200, reason: nil, retry_after: nil)
#
# - Only URLs in SlackConnection::WEBHOOK_URL's shape: https to hooks.slack.com.
# - Net::HTTP with TLS verification on, a 5 s connect and 10 s read/write
#   timeout, a TOTAL_TIMEOUT backstop, no proxy from ENV and no retries of its own.
# - Redirects are never followed (a 3xx is a failed post).
# - At most MAX_BODY_BYTES of the response body are kept, and the connection
#   stops reading after UptimeProbe::MAX_READ_BYTES in all (UptimeProbe::Connection).
# - Never raises for network outcomes, and never puts the URL in a result,
#   a log line or an exception message.
#
# Outcomes: :delivered (2xx); :retry (429 with its Retry-After, capped; 5xx;
# network errors); :rejected (Slack refused the webhook itself: 404/410 or a
# REJECTION_CODES body; the connection is turned off); :failed (any other
# answer, such as 400 invalid_payload: dropped, not retried).
class SlackWebhook
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  TOTAL_TIMEOUT = 20
  MAX_BODY_BYTES = 4.kilobytes
  DEFAULT_RETRY_AFTER = 60
  MAX_RETRY_AFTER = 15.minutes.to_i
  USER_AGENT = "GoodSorcery-Slack/1.0".freeze
  # Slack's error bodies that mean the webhook (or its channel or workspace)
  # is gone or revoked, rather than that this one message was bad.
  REJECTION_CODES = %w[invalid_token action_prohibited channel_not_found channel_is_archived no_service no_team
                       team_disabled team_not_found invalid_team].freeze
  GONE_STATUSES = [ 404, 410 ].freeze
  NETWORK_ERRORS = [ Timeout::Error, IO::TimeoutError, IOError, EOFError, SystemCallError, SocketError, OpenSSL::SSL::SSLError,
                     Net::ProtocolError, Net::HTTPBadResponse, UptimeProbe::ResponseTooLarge ].freeze

  class NotAWebhook < ArgumentError
    def initialize(message = "Not a Slack incoming webhook URL") = super
  end

  Result = Data.define(:outcome, :http_status, :reason, :retry_after) do
    def self.of(outcome, http_status: nil, reason: nil, retry_after: nil) = new(outcome:, http_status:, reason:, retry_after:)

    def delivered? = outcome == :delivered

    def rejected? = outcome == :rejected

    def retry? = outcome == :retry

    def failed? = outcome == :failed

    # "429", "Net::OpenTimeout": the HTTP status or the error class, for logs.
    def log_label = (http_status || reason).to_s
  end

  # endpoint: tests only, a local server to connect to instead of Slack (the
  # request path is still the webhook's).
  def initialize(url, endpoint: nil)
    raise NotAWebhook unless SlackConnection::WEBHOOK_URL.match?(url.to_s)

    @uri = URI(url)
    @endpoint = endpoint || @uri
  end

  def post(payload)
    code, retry_after, body = Timeout.timeout(TOTAL_TIMEOUT) { exchange(JSON.generate(payload)) }
    result_for(code, retry_after, body)
  rescue *NETWORK_ERRORS => error
    Result.of(:retry, reason: error.class.name)
  end

  private
    # [status code, Retry-After header, the body's first MAX_BODY_BYTES].
    def exchange(json)
      body = nil
      connection.start do |http|
        response = http.request(post_request(json)) { |streamed| body = capped_body(streamed) }
        [ response.code.to_i, response["Retry-After"], body ]
      end
    end

    def connection
      UptimeProbe::Connection.new(@endpoint.host, @endpoint.port, nil).tap do |http|
        http.use_ssl = @endpoint.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = http.ssl_timeout = OPEN_TIMEOUT
        http.read_timeout = http.write_timeout = READ_TIMEOUT
        http.max_retries = 0
      end
    end

    def post_request(json)
      Net::HTTP::Post.new(@uri.request_uri, "Content-Type" => "application/json; charset=utf-8", "User-Agent" => USER_AGENT,
                          "Accept-Encoding" => "identity").tap { |request| request.body = json }
    end

    # Keeps the start, drains the rest (the connection's read cap bounds it).
    def capped_body(response)
      body = +""
      response.read_body { |chunk| body << chunk.byteslice(0, [ MAX_BODY_BYTES - body.bytesize, 0 ].max) }
      body
    end

    def result_for(code, retry_after, body)
      return Result.of(:delivered, http_status: code) if code.between?(200, 299)
      return Result.of(:retry, http_status: code, retry_after: retry_after_seconds(retry_after)) if code == 429
      return Result.of(:retry, http_status: code) if code >= 500

      reason = rejection_reason(code, body)
      reason ? Result.of(:rejected, http_status: code, reason:) : Result.of(:failed, http_status: code)
    end

    # Slack's own code when it is a known one, else the status: never free text from the response.
    def rejection_reason(code, body)
      return unless code.between?(400, 499)

      word = body.to_s.strip
      return word if REJECTION_CODES.include?(word)

      "http_#{code}" if GONE_STATUSES.include?(code)
    end

    # Seconds from Retry-After (an HTTP-date or junk gets the default), within 1..MAX_RETRY_AFTER.
    def retry_after_seconds(value)
      seconds = Integer(value.to_s.strip, exception: false) || DEFAULT_RETRY_AFTER
      seconds.clamp(1, MAX_RETRY_AFTER)
    end
end
