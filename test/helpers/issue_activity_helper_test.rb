require "test_helper"

class IssueActivityHelperTest < ActionView::TestCase
  test "sentences name the actor and subject" do
    philip = users(:philip)
    assert_equal "Regressed: seen again after being resolved", activity_sentence(IssueActivity.new(kind: "regressed"))
    assert_includes activity_sentence(IssueActivity.new(kind: "assigned", user: philip, subject_user: philip)), "assigned themselves"
    assert_includes activity_sentence(IssueActivity.new(kind: "resolved")), "A former member"
    assert_includes activity_marker(IssueActivity.new(kind: "note")), "✎"
  end
end
