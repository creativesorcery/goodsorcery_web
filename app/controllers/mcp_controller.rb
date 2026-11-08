# The MCP endpoint (docs/ARCHITECTURE.md §14.2, docs/MCP.md): POST /mcp,
# Streamable HTTP in stateless mode with JSON responses. No cookies, session
# or CSRF (ActionController::API): a personal access token is the only
# credential. Checks, in order: the per-IP limit, the Origin (browsers may
# only call from this instance's own origin, against DNS rebinding), the
# token (401), the per-token limit. The body never reaches params or logs
# (IngestBodyShield) and is capped at Mcp::MAX_BODY_BYTES by the transport.
# GET and DELETE (streams and sessions) are not offered: 405.
class McpController < ActionController::API
  include PersonalAccessTokenAuthentication

  wrap_parameters false

  rate_limit to: Mcp::RATE_PER_IP, within: Mcp::RATE_WINDOW, name: "ip", scope: Mcp::RATE_SCOPE,
             by: -> { request.remote_ip }, with: -> { render_rate_limited }, store: Ingest::RateLimitStore, only: :create
  before_action :reject_foreign_origin, only: :create
  before_action :authenticate_personal_access_token, only: :create
  rate_limit to: Mcp::RATE_PER_TOKEN, within: Mcp::RATE_WINDOW, name: "token", scope: Mcp::RATE_SCOPE,
             by: -> { current_personal_access_token.id }, with: -> { render_rate_limited },
             store: Ingest::RateLimitStore, only: :create
  after_action { no_store }

  def create
    current_personal_access_token.record_usage
    status, headers, body = Time.use_zone("UTC") { Mcp::Endpoint.new(current_personal_access_token, base_url:).answer(rack_request) }
    headers.each { |name, value| response.headers[name] = value }
    self.status = status
    self.response_body = body
  end

  def show = render_method_not_allowed

  def destroy = render_method_not_allowed

  private
    def rack_request = Rack::Request.new(request.env)

    # Where clients reach this instance: GOODSORCERY_PUBLIC_URL, else this request's own origin.
    def base_url = Rails.configuration.x.public_url&.to_s || request.base_url

    def reject_foreign_origin
      origin = request.headers["Origin"]
      return if origin.nil? || origin.downcase.delete_suffix("/") == allowed_origin

      render_json_rpc_error :forbidden, -32000, "forbidden: origin not allowed"
    end

    def allowed_origin
      uri = URI(base_url)
      "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}".downcase
    end

    def render_method_not_allowed
      response.headers["Allow"] = "POST"
      render_json_rpc_error :method_not_allowed, -32000, "method not allowed: POST JSON-RPC messages to this URL"
    end
end
