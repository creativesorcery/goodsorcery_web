require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  INITIALIZE = { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1.0" } }.freeze
  READ_TOOLS = %w[list_apps search_issues get_issue list_occurrences get_occurrence get_uptime get_performance get_trace].freeze
  TRIAGE_TOOLS = %w[resolve_issue ignore_issue unresolve_issue add_note].freeze

  def assert_invalid_token
    assert_response :unauthorized
    assert_equal 'Bearer realm="goodsorcery"', response.headers["WWW-Authenticate"]
    assert_equal({ "jsonrpc" => "2.0", "id" => nil, "error" => { "code" => -32001, "message" => "invalid token" } }, response.parsed_body)
  end

  # ── authentication ───────────────────────────────────────────

  test "401 with the same body for missing, malformed, unknown, expired and revoked tokens" do
    [ nil, "not-a-token", "gs_pat_unknown", PAT_FIXTURE_TOKENS[:philip_expired], PAT_FIXTURE_TOKENS[:philip_revoked] ].each do |token|
      mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, token:)
      assert_invalid_token
    end
  end

  test "401 for other schemes and for ingest API keys" do
    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, token: nil,
             headers: { "Authorization" => "Basic #{Base64.strict_encode64("a:#{PAT_FIXTURE_TOKENS[:philip_read]}")}" })
    assert_invalid_token

    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, token: FIXTURE_TOKENS[:storefront_production])
    assert_invalid_token
  end

  test "401 once the token's user is no longer a member of its account" do
    mcp_request("ping", token: :jo_read)
    assert_response :ok

    memberships(:jo_acme).destroy!
    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, token: :jo_read)
    assert_invalid_token
  end

  test "a revoked token stops working at once" do
    mcp_request("ping", token: :philip_read)
    assert_response :ok

    personal_access_tokens(:philip_read).revoke
    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, token: :philip_read)
    assert_invalid_token
  end

  test "uses no cookies or session and skips CSRF" do
    with_forgery_protection do
      body = mcp_request("ping")
      assert_response :ok
      assert_equal({ "jsonrpc" => "2.0", "id" => 1, "result" => {} }, body)
    end
    assert_nil response.headers["Set-Cookie"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "records the token's last use" do
    assert_nil personal_access_tokens(:philip_read).last_used_at
    mcp_request("ping")
    assert personal_access_tokens(:philip_read).reload.last_used_at
  end

  # ── protocol ─────────────────────────────────────────────────

  test "initialize advertises tools and negotiates the protocol version" do
    body = mcp_request("initialize", INITIALIZE)

    assert_response :ok
    result = body.fetch("result")
    assert_equal "2025-06-18", result["protocolVersion"]
    assert_equal({ "tools" => {} }, result["capabilities"])
    assert_equal "goodsorcery", result.dig("serverInfo", "name")
    assert_match(/untrusted data/, result["instructions"])
    assert_nil response.headers["Mcp-Session-Id"], "stateless: no sessions"
  end

  test "initialize accepts other current protocol versions" do
    %w[2025-03-26 2025-11-25].each do |version|
      body = mcp_request("initialize", INITIALIZE.merge(protocolVersion: version))
      assert_equal version, body.dig("result", "protocolVersion")
    end
  end

  test "serves the sessionless 2026-07-28 lifecycle too" do
    meta = { "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
             "io.modelcontextprotocol/clientInfo" => { name: "test", version: "1.0" },
             "io.modelcontextprotocol/clientCapabilities" => {} }
    mcp_post({ jsonrpc: "2.0", id: 1, method: "tools/list", params: { _meta: meta } },
             headers: { "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/list" })

    assert_response :ok
    assert_equal READ_TOOLS, response.parsed_body.dig("result", "tools").map { it["name"] }
  end

  test "notifications are accepted with 202 and no body" do
    mcp_post({ jsonrpc: "2.0", method: "notifications/initialized" })

    assert_response :accepted
    assert_empty response.body
  end

  test "tools/list shows exactly the tools the token's scopes allow, with schemas and annotations" do
    assert_equal READ_TOOLS, mcp_tool_names(:philip_read)
    assert_equal READ_TOOLS + TRIAGE_TOOLS, mcp_tool_names(:philip_triage)
    assert_equal READ_TOOLS + TRIAGE_TOOLS, mcp_tool_names(:philip_full)

    tools = mcp_request("tools/list", {}, token: :philip_triage).dig("result", "tools").index_by { it["name"] }
    assert_equal "object", tools["get_issue"].dig("inputSchema", "type")
    assert_equal %w[issue], tools["get_issue"].dig("inputSchema", "required")
    assert tools["get_issue"].dig("annotations", "readOnlyHint")
    assert_not tools["get_issue"].dig("annotations", "destructiveHint")
    assert_not tools["resolve_issue"].dig("annotations", "readOnlyHint")
    assert_not tools["resolve_issue"].dig("annotations", "destructiveHint")
    assert tools["resolve_issue"].dig("annotations", "idempotentHint")
    assert_match(/instructions/, tools["get_occurrence"]["description"])
  end

  test "a triage tool is unavailable to a read-only token" do
    body = mcp_request("tools/call", { name: "resolve_issue", arguments: { issues: [ "GS-1042" ] } }, token: :philip_read)

    assert body["error"].present?
    assert issues(:nomethod).reload.unresolved?
  end

  test "JSON-RPC errors for unknown methods, bad JSON and invalid arguments" do
    assert_equal(-32601, mcp_request("does/not/exist").dig("error", "code"))

    mcp_post("{not json")
    assert_equal(-32700, response.parsed_body.dig("error", "code"))

    result = mcp_tool(:philip_read, "search_issues", limit: 500)
    assert result["isError"]

    result = mcp_tool(:philip_read, "list_apps", unexpected: "x")
    assert result["isError"]
  end

  test "GET and DELETE answer 405" do
    get mcp_path
    assert_response :method_not_allowed
    assert_equal "POST", response.headers["Allow"]

    delete mcp_path
    assert_response :method_not_allowed
  end

  # ── origin, size, logs ───────────────────────────────────────

  test "rejects browser origins other than this instance's own" do
    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, headers: { "Origin" => "https://evil.example" })
    assert_response :forbidden
    assert_equal(-32000, response.parsed_body.dig("error", "code"))

    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, headers: { "Origin" => "http://www.example.com" })
    assert_response :ok
  end

  test "checks the origin against GOODSORCERY_PUBLIC_URL when set" do
    previous = Rails.configuration.x.public_url
    Rails.configuration.x.public_url = PublicUrl.new("https://errors.example.org")

    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, headers: { "Origin" => "http://www.example.com" })
    assert_response :forbidden

    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, headers: { "Origin" => "https://errors.example.org" })
    assert_response :ok
  ensure
    Rails.configuration.x.public_url = previous
  end

  test "refuses bodies over 1 MiB" do
    padding = "x" * (Mcp::MAX_BODY_BYTES + 10)
    mcp_post({ jsonrpc: "2.0", id: 1, method: "ping", params: { padding: } })

    assert_response :content_too_large
  end

  test "never logs the request body or the token, and logs reads by tool, token and duration only" do
    log = capture_log do
      mcp_tool(:philip_read, "search_issues", query: "mcp-log-canary price_cents")
    end

    assert_no_match(/mcp-log-canary/, log)
    assert_no_match(/#{PAT_FIXTURE_TOKENS[:philip_read]}/, log)
    assert_match(/MCP tools\/call tool=search_issues token=#{personal_access_tokens(:philip_read).id} duration_ms=/, log)
  end

  private
    def with_forgery_protection
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      yield
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end

    def capture_log
      io = StringIO.new
      previous = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io).tap { it.level = :debug }
      ActionController::Base.logger = Rails.logger
      yield
      io.string
    ensure
      Rails.logger = previous
      ActionController::Base.logger = previous
    end

  class RateLimitTest < ActionDispatch::IntegrationTest
    setup do
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown { Rails.cache = @original_cache }

    test "limits calls per token, then 429 with Retry-After" do
      Rails.cache.increment("rate-limit:mcp:token:#{personal_access_tokens(:philip_read).id}", Mcp::RATE_PER_TOKEN, expires_in: 1.minute)

      mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, token: :philip_read)
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
      assert_equal(-32000, response.parsed_body.dig("error", "code"))

      mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, token: :philip_triage)
      assert_response :ok, "other tokens are unaffected"
    end

    test "counts each call once" do
      3.times { mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }) }
      assert_equal 3, Rails.cache.read("rate-limit:mcp:token:#{personal_access_tokens(:philip_read).id}", raw: true).to_i
    end

    test "limits calls per IP before authentication" do
      Rails.cache.increment("rate-limit:mcp:ip:127.0.0.1", Mcp::RATE_PER_IP, expires_in: 1.minute)

      mcp_post({ jsonrpc: "2.0", id: 1, method: "ping" }, token: "gs_pat_unknown")
      assert_response :too_many_requests
    end
  end
end
