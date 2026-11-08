require "mcp/server/transports/streamable_http_transport"

# One MCP request (docs/ARCHITECTURE.md §14.2): an SDK server holding the
# tools the token's scopes allow and an Mcp::Context for the token's
# account, behind the SDK's Streamable HTTP transport in stateless mode with
# plain JSON responses (no sessions, no SSE). The controller has already
# authenticated the token, checked the Origin and applied the rate limits.
#
# Reads are logged by tool name, token id and duration only, never their
# arguments (instrumentation_callback). Exceptions in tools reach
# Rails.error; the client sees only "Internal error calling tool …".
#
#   status, headers, body = Mcp::Endpoint.new(token, base_url:).answer(Rack::Request.new(env))
class Mcp::Endpoint
  def initialize(token, base_url:)
    @token = token
    @base_url = base_url
  end

  def answer(request) = transport.handle_request(request)

  private
    def transport
      MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true, enable_json_response: true,
        dns_rebinding_protection: false, max_request_bytes: Mcp::MAX_BODY_BYTES)
    end

    def server
      MCP::Server.new(name: Mcp::SERVER_NAME, title: Mcp::SERVER_TITLE, version: Mcp::VERSION,
        instructions: Mcp::INSTRUCTIONS, capabilities: { tools: {} }, tools: Mcp::Catalog.tools_for(@token).map(&:sdk_tool),
        server_context: Mcp::Context.new(@token, base_url: @base_url), configuration:)
    end

    def configuration
      MCP::Configuration.new(instrumentation_callback: method(:log_request), exception_reporter: method(:report_exception))
    end

    # Method, tool name, token id and duration: nothing from the arguments.
    def log_request(data)
      tool = data[:tool_name].to_s[/\A[a-z_]{1,40}\z/]
      Rails.logger.info("MCP #{data[:method].to_s[/\A[a-z\/_]{1,40}\z/]}#{" tool=#{tool}" if tool} " \
                        "token=#{@token.id} duration_ms=#{(data[:duration].to_f * 1000).round(1)}#{" error=#{data[:error]}" if data[:error]}")
    end

    def report_exception(exception, _server_context)
      Rails.error.report(exception, handled: true, source: "mcp", context: { personal_access_token_id: @token.id })
    end
end
