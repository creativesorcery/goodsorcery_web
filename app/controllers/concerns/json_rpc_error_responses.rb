# JSON-RPC 2.0 error bodies for the MCP endpoint's HTTP-level refusals
# (401, 403, 405, 429), answered before any request is parsed, so the id is
# null. Messages are fixed strings and never echo the request.
module JsonRpcErrorResponses
  extend ActiveSupport::Concern

  private
    def render_json_rpc_error(status, code, message)
      render json: { jsonrpc: "2.0", id: nil, error: { code:, message: } }, status:
    end

    def render_rate_limited
      response.headers["Retry-After"] = Mcp::RATE_WINDOW.to_i.to_s
      render_json_rpc_error :too_many_requests, -32000, "rate limited: too many requests, retry in a minute"
    end
end
