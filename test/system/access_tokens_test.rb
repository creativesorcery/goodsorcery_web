require "application_system_test_case"

class AccessTokensSystemTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  setup { sign_in }

  test "creating a token shows it once with client tabs, then revoking it" do
    visit_connected access_tokens_path
    type_into find_field("Name"), "Laptop Claude"
    press find_field("scope_triage", visible: :all)
    press find_button("Create token")

    assert_selector "h2", text: "Copy your token now"
    plaintext = find("#created_access_token code").text
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
