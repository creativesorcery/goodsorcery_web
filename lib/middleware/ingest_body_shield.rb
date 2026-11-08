# Stops Rails from parsing the ingest request body into params, so captured
# error data never reaches `params`, the request log ("Parameters: {}") or any
# exception page. It covers the single and the batch endpoint
# (/api/v1/events, /api/v1/events/batch) and the performance endpoints
# (/api/v1/apm/metrics, /api/v1/apm/traces), and the MCP endpoint (/mcp),
# whose JSON-RPC bodies carry tool arguments and notes; the controllers read
# only `request.body`.
#
# The path is normalised the same way the router normalises it (duplicate and
# trailing slashes) and an optional format suffix (".json") is accepted, so no
# spelling of the ingest URL that routes to the controller slips past the shield.
#
# Rack middleware must define #call; this is the one sanctioned exception to
# the project's no-`call` rule.
class IngestBodyShield
  PATH = %r{\A/(?:api/v1/(?:events(?:/batch)?|apm/(?:metrics|traces))|mcp)(?:\.[^/]*)?\z}

  def initialize(app) = @app = app

  def call(env)
    env["action_dispatch.request.request_parameters"] = {} if ingest_path?(env["PATH_INFO"])
    @app.call(env)
  end

  private
    def ingest_path?(path)
      ActionDispatch::Journey::Router::Utils.normalize_path(path.to_s.squeeze("/")).match?(PATH)
    end
end
