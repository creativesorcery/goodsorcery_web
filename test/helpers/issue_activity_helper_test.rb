require "test_helper"

class IssueActivityHelperTest < ActionView::TestCase
  test "sentences name the actor and subject" do
    philip = users(:philip)
    assert_equal "Regressed: seen again after being resolved", activity_sentence(IssueActivity.new(kind: "regressed"))
    assert_includes activity_sentence(IssueActivity.new(kind: "assigned", user: philip, subject_user: philip)), "assigned themselves"
    assert_includes activity_sentence(IssueActivity.new(kind: "resolved")), "A former member"
    assert_includes activity_marker(IssueActivity.new(kind: "note")), "✎"
    assert_equal "Reached production: first seen there after other environments",
      activity_sentence(IssueActivity.new(kind: "reached_production"))
    assert_includes activity_marker(IssueActivity.new(kind: "reached_production")), "text-coral-300"
  end

  test "changes made through the MCP endpoint say so" do
    sentence = activity_sentence(IssueActivity.new(kind: "resolved", user: users(:philip), via: "mcp"))
    assert_includes sentence, "resolved this"
    assert_includes sentence, "via MCP"
    assert_not_includes activity_sentence(IssueActivity.new(kind: "resolved", user: users(:philip))), "via MCP"
  end
end
