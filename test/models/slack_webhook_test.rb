require "test_helper"
require_relative "../test_helpers/slack_test_helper"

# Real HTTP against servers on 127.0.0.1 through SlackWebhook's endpoint
# option; nothing reaches Slack.
class SlackWebhookTest < ActiveSupport::TestCase
  include SlackTestHelper

  teardown { @server&.close }

  def serve(&responder)
    @server = LocalHttpServer.new(&responder)
  end

  def webhook(scheme: "http")
    SlackWebhook.new(WEBHOOK_URL, endpoint: URI("#{scheme}://127.0.0.1:#{@server.port}"))
  end

  def post_with(status, headers = {}, body = "")
    serve { |_, client| client.write(http_response(status, headers, body)) }
    webhook.post({ text: "hi" })
  end

  test "posts the JSON payload to the webhook's path" do
    bodies = []
    serve do |request, client|
      bodies << client.read(request[/^Content-Length: (\d+)/i, 1].to_i)
      client.write(http_response(200, {}, "ok"))
    end

    result = webhook.post({ text: "hi", blocks: [] })
    head = @server.requests.sole

    assert_predicate result, :delivered?
    assert_equal({ "text" => "hi", "blocks" => [] }, JSON.parse(bodies.sole))
    assert_equal 200, result.http_status
    assert_match %r{\APOST /services/T0ACMEFIX/B0STOREFIX/#{SLACK_SECRET}0123456789 HTTP/1.1\r\n}, head
    assert_includes head, "Content-Type: application/json; charset=utf-8\r\n"
    assert_includes head, "User-Agent: GoodSorcery-Slack/1.0\r\n"
  end

  test "a 429 is retried after Retry-After, capped, or a default when it's missing or junk" do
    assert_equal [ :retry, 429, 7 ], post_with(429, "Retry-After" => "7").then { |r| [ r.outcome, r.http_status, r.retry_after ] }
    @server.close
    assert_equal SlackWebhook::MAX_RETRY_AFTER, post_with(429, "Retry-After" => "86400").retry_after
    @server.close
    assert_equal SlackWebhook::DEFAULT_RETRY_AFTER, post_with(429, "Retry-After" => "Wed, 21 Oct 2026 07:28:00 GMT").retry_after
    @server.close
    assert_equal 1, post_with(429, "Retry-After" => "-5").retry_after
  end

  test "a 5xx is retried without a set wait" do
    result = post_with(503, {}, "rollup_error")

    assert_predicate result, :retry?
    assert_nil result.retry_after
  end

  test "404 and 410 reject the webhook" do
    assert_equal [ :rejected, "no_service" ], post_with(404, {}, "no_service").then { |r| [ r.outcome, r.reason ] }
    @server.close
    assert_equal [ :rejected, "channel_is_archived" ], post_with(410, {}, "channel_is_archived").then { |r| [ r.outcome, r.reason ] }
    @server.close
    assert_equal [ :rejected, "http_404" ], post_with(404, {}, "<html>gone</html>").then { |r| [ r.outcome, r.reason ] }
  end

  test "a 4xx naming a revoked token or a lost channel rejects the webhook; other 4xx just fail" do
    assert_equal [ :rejected, "invalid_token" ], post_with(403, {}, "invalid_token").then { |r| [ r.outcome, r.reason ] }
    @server.close
    assert_equal [ :rejected, "channel_not_found" ], post_with(400, {}, "channel_not_found\n").then { |r| [ r.outcome, r.reason ] }
    @server.close
    assert_equal [ :failed, nil ], post_with(400, {}, "invalid_payload").then { |r| [ r.outcome, r.reason ] }
  end

  test "redirects are never followed" do
    result = post_with(302, "Location" => "https://evil.example/steal")

    assert_predicate result, :failed?
    assert_equal 1, @server.requests.size
  end

  test "keeps only the start of a long body" do
    serve { |_, client| client.write(http_response(400, {}, "x" * 20_000)) }
    assert_predicate webhook.post({ text: "hi" }), :failed?

    streamed = Object.new
    def streamed.read_body = [ "a" * 3_000, "b" * 3_000, "c" * 3_000 ].each { |chunk| yield chunk }
    body = SlackWebhook.new(WEBHOOK_URL).send(:capped_body, streamed)
    assert_equal SlackWebhook::MAX_BODY_BYTES, body.bytesize
    assert body.end_with?("b")
  end

  test "an endless response is cut off by the connection's read cap and retried" do
    serve { |_, client| client.write(http_response(200, {}, "x" * (UptimeProbe::MAX_READ_BYTES * 2))) }

    result = webhook.post({ text: "hi" })

    assert_predicate result, :retry?
    assert_equal "UptimeProbe::ResponseTooLarge", result.reason
  end

  test "network errors are retried and named by class only" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close

    result = SlackWebhook.new(WEBHOOK_URL, endpoint: URI("http://127.0.0.1:#{port}")).post({ text: "hi" })

    assert_predicate result, :retry?
    assert_equal "Errno::ECONNREFUSED", result.log_label
  end

  test "verifies the TLS certificate" do
    @server = tls_server(Queue.new)

    result = webhook(scheme: "https").post({ text: "hi" })

    assert_predicate result, :retry?
    assert_equal "OpenSSL::SSL::SSLError", result.reason
  end

  test "the client is configured with short timeouts, TLS verification and no proxy" do
    http = SlackWebhook.new(WEBHOOK_URL).send(:connection)

    assert_equal [ 5, 10, 10 ], [ http.open_timeout, http.read_timeout, http.write_timeout ]
    assert http.use_ssl?
    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    assert_equal [ "hooks.slack.com", 443 ], [ http.address, http.port ]
    assert_not http.proxy?
  end

  test "refuses any URL that isn't a Slack webhook, without echoing it" do
    error = assert_raises(SlackWebhook::NotAWebhook) { SlackWebhook.new("https://evil.example/services/T1/B2/secretsecret") }

    assert_not_includes error.message, "secretsecret"
  end
end
