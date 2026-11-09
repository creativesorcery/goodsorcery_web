require "application_system_test_case"

class AccessTokensSystemTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  setup { sign_in }

  test "the MCP server page shows placeholder client snippets until a token is created" do
    visit_connected access_tokens_path
    assert_selector "h1", text: "MCP server"
    assert_selector "#connect_client h2", text: "Connect a client"
    assert_selector "#mcp_server_url", text: %r{/mcp\z}
    press find("#mcp_server_url ~ button")
    # Only the visible word flashes (headless Chrome may refuse the clipboard);
    # the screen-reader context stays, so the accessible name reports the result.
    assert_selector "#mcp_server_url ~ button [data-clipboard-target=label]", text: /\ACop(ied ✓|y failed)\z/
    assert_selector "#mcp_server_url ~ button .sr-only", text: "server URL", visible: :all
    assert_selector "#mcp_server_url ~ button [data-clipboard-target=label]", exact_text: "Copy"
    assert_selector "#client-claude_code", text: "Bearer <your-token>"

    press find("#client-tab-codex")
    assert_selector "#client-codex", text: %(export GOODSORCERY_TOKEN="<your-token>")
    assert_no_selector "#client-claude_code", visible: true
    assert_selector "[role=tablist][aria-label='AI client']", count: 1
  end

  test "creating a token shows it once with client tabs, then revoking it" do
    visit_connected access_tokens_path
    type_into find_field("Name"), "Laptop Claude"
    press find_field("scope_triage", visible: :all)
    press find_button("Create token")

    assert_selector "h2", text: "Copy your token now"
    assert_no_selector "#connect_client"
    assert_selector "[role=tablist][aria-label='AI client']", count: 1
    plaintext = find("#created_access_token_value").text
    assert_match(/\Ags_pat_/, plaintext)
    assert_selector "#client-claude_code", text: "claude mcp add --transport http goodsorcery"
    assert_no_selector "#client-cursor", visible: true

    press find("#client-tab-cursor")
    assert_selector "#client-cursor", text: "mcpServers"
    assert_no_selector "#client-claude_code", visible: true

    token = PersonalAccessToken.authenticate(plaintext)
    assert_equal %w[read triage], token.scopes

    visit_connected access_tokens_path
    assert_no_text plaintext
    page.execute_script("window.confirm = () => true")
    press find("##{dom_id(token)} button", text: "Revoke")
    assert_text "Laptop Claude is revoked."
    assert token.reload.revoked?
  end
end
