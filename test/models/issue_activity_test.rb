require "test_helper"

class IssueActivityTest < ActiveSupport::TestCase
  test "notes need a body of at most 2,000 characters" do
    issue = issues(:nomethod)

    assert_not issue.activities.new(kind: "note", user: users(:jo)).valid?
    assert_not issue.activities.new(kind: "note", body: "x" * 2_001).valid?
    assert issue.activities.new(kind: "note", body: "On it").valid?
  end

  test "non-note activities carry no body" do
    assert_not issues(:nomethod).activities.new(kind: "resolved", body: "nope").valid?
  end

  test "kind is validated" do
    assert_not issues(:nomethod).activities.new(kind: "merged").valid?
  end

  test "recent orders newest first" do
    assert_equal %w[note assigned], issues(:nomethod).activities.recent.pluck(:kind)
  end

  test "record_all inserts one row per issue" do
    ids = issues(:card_error, :billing_timeout).map(&:id)

    assert_difference -> { IssueActivity.ignored.count } => 2 do
      IssueActivity.record_all(ids, kind: :ignored, user: users(:jo))
    end
    assert_equal [ users(:jo).id ], IssueActivity.ignored.distinct.pluck(:user_id)
  end
end
