# JSON-RPC calls to POST /mcp in integration tests.
#
#   result = mcp_tool(:philip_read, "get_issue", issue: "GS-1042")
#   result["structuredContent"]["short_id"]  # => "GS-1042"
module McpTestHelper
  MCP_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }.freeze

  def mcp_post(body, token: :philip_read, headers: {})
    raw = token.is_a?(Symbol) ? PAT_FIXTURE_TOKENS.fetch(token) : token
    auth = raw ? { "Authorization" => "Bearer #{raw}" } : {}
    post mcp_path, params: body.is_a?(String) ? body : body.to_json,
      headers: MCP_HEADERS.merge("MCP-Protocol-Version" => "2025-06-18").merge(auth).merge(headers)
  end

  def mcp_request(method, params = {}, token: :philip_read, id: 1)
    mcp_post({ jsonrpc: "2.0", id:, method:, params: }, token:)
    response.parsed_body
  end

  # The tools/call result (content, structuredContent, isError).
  def mcp_tool(token, name, **arguments)
    body = mcp_request("tools/call", { name:, arguments: }, token:)
    assert_response :ok
    assert_nil body["error"], body.inspect
    body.fetch("result")
  end

  def mcp_text(result) = result.fetch("content").map { |item| item["text"] }.join("\n")

  def mcp_tool_names(token)
    mcp_request("tools/list", {}, token:).dig("result", "tools").map { |tool| tool["name"] }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include McpTestHelper
end
