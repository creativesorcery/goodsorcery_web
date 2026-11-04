require "socket"
require "openssl"

# Support for uptime tests. Nothing here reaches the network: probes connect
# to servers on 127.0.0.1 through an injected resolver, and jobs use a fake
# probe.
#
#   with_fake_probe(up_result, down_result("timeout")) { |probe| UptimeCheckJob.perform_now(id) }
#   server = LocalHttpServer.new { |request, client| client.write(http_response(200)) }
#   UptimeProbe.new("http://status.example.test:#{server.port}/", guard: local_guard).check
module UptimeTestHelper
  SECRET = "uptime-fixture-secret".freeze

  # Returns its results in order from #check.
  class FakeProbe
    attr_reader :calls

    def initialize(results)
      @results = results.dup
      @calls = 0
    end

    def check
      @calls += 1
      @results.shift || raise("FakeProbe has no results left")
    end
  end

  # Accepts connections on 127.0.0.1 and hands each request (its head as a
  # string) and the client socket to the block. The connection closes when the
  # block returns.
  class LocalHttpServer
    attr_reader :port, :requests

    def initialize(server = TCPServer.new("127.0.0.1", 0), &responder)
      @server = server
      @port = server.to_io.addr[1]
      @requests = []
      @thread = Thread.new { serve(responder) }
    end

    def close
      @thread.kill.join
      @server.close
    end

    private
      def serve(responder)
        loop do
          client = @server.accept
          answer(client, responder)
        rescue OpenSSL::SSL::SSLError, SystemCallError, IOError
          next
        end
      end

      def answer(client, responder)
        request = read_head(client)
        @requests << request
        responder.call(request, client)
      rescue SystemCallError, IOError
        nil
      ensure
        client.close
      end

      def read_head(client)
        head = +""
        while (line = client.gets)
          head << line
          break if line == "\r\n"
        end
        head
      end
  end

  def http_response(status, headers = {}, body = "")
    lines = [ "HTTP/1.1 #{status} Status", *headers.map { |name, value| "#{name}: #{value}" }, "Content-Length: #{body.bytesize}",
              "Connection: close" ]
    "#{lines.join("\r\n")}\r\n\r\n#{body}"
  end

  def up_result(response_time_ms = 120, http_status: 200)
    UptimeProbe::Result.up(response_time_ms:, http_status:)
  end

  def down_result(error_kind = "timeout", http_status: nil)
    UptimeProbe::Result.down(error_kind, http_status:)
  end

  # Every UptimeProbe.new inside the block returns one FakeProbe.
  def with_fake_probe(*results, &block) = with_probe(FakeProbe.new(results), &block)

  # Every UptimeProbe.new inside the block returns this object.
  def with_probe(probe)
    UptimeProbe.singleton_class.define_method(:new) { |*, **| probe }
    yield probe
  ensure
    UptimeProbe.singleton_class.remove_method(:new)
  end

  # Resolves every name (or the mapped ones) to 127.0.0.1, which is the only
  # private address it lets through.
  def local_guard(addresses = {})
    resolver = ->(hostname, _timeout) { Array(addresses.fetch(hostname, "127.0.0.1")).map { |ip| IPAddr.new(ip) } }
    UptimeProbe::AddressGuard.new(allow_private: false, allowed_ips: [ "127.0.0.1" ], resolver:)
  end

  def capture_log
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output).tap { |log| log.level = :debug }
    Rails.logger.broadcast_to(logger)
    yield
    output.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  # A TLS server with a self-signed certificate (so verification fails) that
  # records the SNI name each client sends.
  def tls_server(sni_names)
    context = OpenSSL::SSL::SSLContext.new
    context.key, context.cert = self_signed_certificate
    context.servername_cb = proc do |_socket, name|
      sni_names << name
      nil # keep this context
    end
    LocalHttpServer.new(OpenSSL::SSL::SSLServer.new(TCPServer.new("127.0.0.1", 0), context)) { |_request, client| client.write(http_response(200)) }
  end

  def self_signed_certificate
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=uptime-test")
    cert.public_key = key
    cert.not_before = 1.minute.ago
    cert.not_after = 1.hour.from_now
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    [ key, cert ]
  end
end
