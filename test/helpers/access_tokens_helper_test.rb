require "test_helper"

class AccessTokensHelperTest < ActionView::TestCase
  test "mcp_endpoint_url is the request's base URL plus /mcp without a public URL" do
    previous = Rails.configuration.x.public_url
    Rails.configuration.x.public_url = nil
    assert_equal "http://test.host/mcp", mcp_endpoint_url
  ensure
    Rails.configuration.x.public_url = previous
  end

  test "snippets with the placeholder put it wherever a token would go" do
    placeholder = AccessTokensHelper::TOKEN_PLACEHOLDER

    assert_includes mcp_client_snippets("claude_code", placeholder).to_h.fetch("terminal"), "Authorization: Bearer #{placeholder}"
    codex = mcp_client_snippets("codex", placeholder).to_h
    assert_equal "export GOODSORCERY_TOKEN=\"#{placeholder}\"", codex.fetch("shell profile")
    assert_not_includes codex.fetch("~/.codex/config.toml"), placeholder
    assert_equal "Bearer #{placeholder}",
      JSON.parse(mcp_client_snippets("cursor", placeholder).to_h.fetch("~/.cursor/mcp.json")).dig("mcpServers", "goodsorcery", "headers", "Authorization")
    assert_not_includes mcp_client_snippets("vscode", placeholder).to_h.fetch(".vscode/mcp.json"), placeholder
  end

  test "every client has snippets" do
    AccessTokensHelper::CLIENTS.each_key { |client| assert mcp_client_snippets(client, "x").any?, client }
  end

  test "the guide link points at docs/MCP.md in the public repository" do
    assert_equal "https://github.com/creativesorcery/goodsorcery_web/blob/main/docs/MCP.md", AccessTokensHelper::MCP_GUIDE_URL
    assert AccessTokensHelper::MCP_GUIDE_URL.start_with?(ApplicationHelper::DEFAULT_DOCS_URL.sub("/tree/", "/blob/"))
  end
end
