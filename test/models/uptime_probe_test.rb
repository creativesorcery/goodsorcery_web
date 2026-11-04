require "test_helper"
require_relative "../test_helpers/uptime_test_helper"

# Real HTTP against servers on 127.0.0.1; names resolve through an injected
# resolver, so no test touches DNS or the network.
class UptimeProbeTest < ActiveSupport::TestCase
  include UptimeTestHelper

  teardown { @server&.close }

  def serve(&responder)
    @server = LocalHttpServer.new(&responder)
  end

  def url(path = "/up", host: "status.example.test")
    "http://#{host}:#{@server.port}#{path}"
  end

  def probe(target = url, **options)
    UptimeProbe.new(target, guard: local_guard, **options)
  end

  test "a 2xx response is up, with the response time and status" do
    serve { |_, client| client.write(http_response(204)) }

    result = probe.check

    assert_predicate result, :up?
    assert_equal 204, result.http_status
    assert_nil result.error_kind
    assert_kind_of Integer, result.response_time_ms
  end

  test "connects to the vetted address while sending the original Host, path and query" do
    serve { |_, client| client.write(http_response(200)) }

    probe(url("/up?token=#{SECRET}")).check
    head = @server.requests.sole

    assert_match %r{\AGET /up\?token=#{SECRET} HTTP/1.1\r\n}, head
    assert_includes head, "Host: status.example.test:#{@server.port}\r\n"
    assert_includes head, "User-Agent: GoodSorcery-Uptime/1.0\r\n"
    assert_includes head, "Accept-Encoding: identity\r\n"
    assert_no_match(/^Cookie|^Authorization/i, head)
  end

  test "resolves once per hop and ignores proxies from ENV" do
    serve { |_, client| client.write(http_response(200)) }
    lookups = []
    resolver = ->(host, _timeout) { (lookups << host) && [ IPAddr.new("127.0.0.1") ] }
    guard = UptimeProbe::AddressGuard.new(allow_private: false, allowed_ips: [ "127.0.0.1" ], resolver:)

    result = with_env("http_proxy" => "http://10.255.0.1:3128", "HTTP_PROXY" => "http://10.255.0.1:3128") do
      UptimeProbe.new(url, guard:).check
    end

    assert_predicate result, :up?
    assert_equal [ "status.example.test" ], lookups
  end

  test "sends the host name as SNI over TLS and verifies the certificate" do
    sni_names = Queue.new
    @server = tls_server(sni_names)

    result = probe("https://secure.example.test:#{@server.port}/").check

    assert_equal "tls_error", result.error_kind
    assert_equal "secure.example.test", sni_names.pop(timeout: 2)
  end

  test "a 3xx without a usable Location is the final response and up" do
    serve { |_, client| client.write(http_response(302, "Location" => "ftp://files.example.test/")) }

    result = probe.check

    assert_predicate result, :up?
    assert_equal 302, result.http_status
    assert_equal 1, @server.requests.size
  end

  test "any other status is down with the code kept" do
    serve { |_, client| client.write(http_response(503)) }

    result = probe.check

    assert_predicate result, :down?
    assert_equal [ "http_status", 503 ], [ result.error_kind, result.http_status ]
    assert_kind_of Integer, result.response_time_ms
  end

  test "follows redirects, re-vetting each hop" do
    serve do |head, client|
      client.write(head.start_with?("GET /final") ? http_response(200) : http_response(301, "Location" => "/final"))
    end

    result = probe.check

    assert_predicate result, :up?
    assert_equal 200, result.http_status
    assert_equal 2, @server.requests.size
  end

  test "a redirect to a private address ends the check as blocked" do
    serve { |_, client| client.write(http_response(302, "Location" => "http://169.254.169.254/latest/meta-data/")) }

    result = probe.check

    assert_equal [ "down", "blocked_address" ], [ result.status, result.error_kind ]
  end

  test "a redirect to a name that resolves privately is blocked" do
    serve { |_, client| client.write(http_response(307, "Location" => "http://internal.example.test/")) }
    guard = local_guard("internal.example.test" => "10.0.0.8")

    result = UptimeProbe.new(url, guard:).check

    assert_equal "blocked_address", result.error_kind
  end

  test "stops after MAX_REDIRECTS redirects and takes the last 3xx as final" do
    serve { |_, client| client.write(http_response(302, "Location" => "/again")) }

    result = probe.check

    assert_equal UptimeProbe::MAX_REDIRECTS + 1, @server.requests.size
    assert_equal [ "up", 302 ], [ result.status, result.http_status ]
  end

  test "a silent server times out within the budget" do
    serve { sleep 5 }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = probe(timeout: 0.4).check

    assert_equal [ "down", "timeout" ], [ result.status, result.error_kind ]
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end

  test "a trickling body runs out of budget between chunks" do
    serve do |_, client|
      client.write("HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n")
      20.times { client.write("x") && sleep(0.1) }
    end

    assert_equal "timeout", probe(timeout: 0.5).check.error_kind
  end

  test "reads at most MAX_BODY_BYTES of the body" do
    serve do |_, client|
      client.write("HTTP/1.1 200 OK\r\nContent-Length: #{10.megabytes}\r\n\r\n")
      client.write("x" * 128.kilobytes)
      sleep 5 # never finishes the body: only a capped read returns in time
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = probe(timeout: 2).check

    assert_predicate result, :up?
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.5
  end

  test "maps connection outcomes to error kinds" do
    port = TCPServer.new("127.0.0.1", 0).then { |server| server.addr[1].tap { server.close } }
    assert_equal "connection_refused", probe("http://status.example.test:#{port}/").check.error_kind

    serve { |_, client| client.write("NOT HTTP AT ALL\r\n\r\n") }
    assert_equal "connection_error", probe.check.error_kind
  end

  test "a connection closed without a response is a connection error" do
    serve { |_, client| client.close }

    assert_equal "connection_error", probe.check.error_kind
  end

  test "DNS failures and DNS timeouts" do
    no_answer = UptimeProbe::AddressGuard.new(allow_private: false, resolver: ->(*) { [] })
    failing = UptimeProbe::AddressGuard.new(allow_private: false, resolver: ->(*) { raise SocketError, "getaddrinfo failed" })
    slow = UptimeProbe::AddressGuard.new(allow_private: false, resolver: ->(*) { raise IO::TimeoutError, "resolve timed out" })

    assert_equal "dns_failure", UptimeProbe.new("https://gone.example.test/", guard: no_answer).check.error_kind
    assert_equal "dns_failure", UptimeProbe.new("https://gone.example.test/", guard: failing).check.error_kind
    assert_equal "timeout", UptimeProbe.new("https://slow.example.test/", guard: slow).check.error_kind
  end

  test "blocked first hops never connect" do
    %w[http://127.0.0.1/ http://localhost/ http://[::1]/ http://169.254.169.254/ http://10.1.1.1/].each do |target|
      assert_equal "blocked_address", UptimeProbe.new(target, guard: UptimeProbe::AddressGuard.new(allow_private: false)).check.error_kind
    end
  end

  test "an unexpected error is a connection error, logged by class name only" do
    guard = UptimeProbe::AddressGuard.new(allow_private: false, resolver: ->(*) { raise "boom https://x.example/?token=#{SECRET}" })

    log = capture_log { assert_equal "connection_error", UptimeProbe.new("https://x.example/", guard:, monitor_id: 7).check.error_kind }

    assert_includes log, "Uptime check 7 failed: RuntimeError"
    assert_not_includes log, SECRET
  end

  private
    def with_env(values)
      previous = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
end
