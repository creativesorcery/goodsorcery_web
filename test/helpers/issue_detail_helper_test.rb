require "test_helper"

class IssueDetailHelperTest < ActionView::TestCase
  test "the AI prompt names the short id the MCP tools take and the app, nothing captured" do
    issue = issues(:nomethod)
    prompt = issue_ai_prompt(issue)

    assert_equal "Use the Good Sorcery MCP server to look into issue #{issue.short_id} in the storefront app " \
                 "and suggest a fix. Start with get_issue for #{issue.short_id}.", prompt
    assert_match Issue::SHORT_ID, issue.short_id
    [ issue.message, issue.culprit, issue.transaction_name, issue.exception_class ].compact_blank.each do |captured|
      assert_not_includes prompt, captured
    end
  end

  test "the AI prompt adds the slug when the app's name differs from it" do
    issue = issues(:nomethod)
    issue.project.name = "  Storefront   Web "

    assert_includes issue_ai_prompt(issue), "in the Storefront Web app (slug: storefront) and suggest a fix."
  end

  test "MCP setup is offered only without an active token for the current account" do
    Current.session = users(:philip).sessions.create!(account: accounts(:acme))
    assert_not mcp_setup_needed?, "philip has active tokens"

    remove_instance_variable(:@mcp_setup_needed)
    PersonalAccessToken.revoke_all(user_id: users(:philip).id)
    assert_queries_count(1) { assert mcp_setup_needed?, "revoked and expired tokens don't count" }
    assert_queries_count(0) { assert mcp_setup_needed?, "asked once per page" }
  end

  test "another account's token doesn't count" do
    Current.session = users(:jo).sessions.create!(account: accounts(:acme))
    users(:jo).personal_access_tokens.update_all(account_id: accounts(:umbrella).id)

    assert mcp_setup_needed?
  end
end
