require "test_helper"

class IssueTest < ActiveSupport::TestCase
  test "short id combines the project prefix and number" do
    assert_equal "GS-1042", issues(:nomethod).short_id
    assert_equal "GS-1042", issues(:nomethod).to_param
    assert_equal "BA-7", issues(:billing_timeout).short_id
  end

  test "short id needs no extra query when loaded through the project" do
    project = projects(:storefront)
    issues = project.issues.to_a
    assert_queries_count(0) { issues.map(&:short_id) }
  end

  test "find_by_short_id! is scoped to the relation" do
    assert_equal issues(:nomethod), projects(:storefront).issues.find_by_short_id!("GS-1042")
    assert_equal issues(:nomethod), projects(:storefront).issues.find_by_short_id!("gs-1042")
    assert_raises(ActiveRecord::RecordNotFound) { projects(:billing).issues.find_by_short_id!("GS-1042") }
    assert_raises(ActiveRecord::RecordNotFound) { projects(:storefront).issues.find_by_short_id!("GS-") }
    assert_raises(ActiveRecord::RecordNotFound) { projects(:storefront).issues.find_by_short_id!(nil) }
  end

  test "new and regressed" do
    assert issues(:nomethod).new?
    assert_not issues(:card_error).new?
    assert issues(:regressed).regressed?
    assert_not issues(:nomethod).regressed?

    issues(:regressed).status = "resolved"
    assert_not issues(:regressed).regressed?
  end

  test "status and level enums validate" do
    issue = issues(:nomethod)
    issue.status = "snoozed"
    issue.level = "debug"
    assert_not issue.valid?
    assert issue.errors.of_kind?(:status, :inclusion)
    assert issue.errors.of_kind?(:level, :inclusion)
  end

  test "fingerprint label" do
    assert_equal issues(:nomethod).fingerprint.first(12), issues(:nomethod).fingerprint_label
    assert_equal 12, issues(:nomethod).fingerprint_label.length
  end

  test "number and fingerprint are unique per project" do
    copy = projects(:storefront).issues.new(issues(:nomethod).attributes.except("id", "search_text"))
    assert_raises(ActiveRecord::RecordNotUnique) { copy.save!(validate: false) }

    other = projects(:billing).issues.new(issues(:nomethod).attributes.except("id", "search_text", "project_id"))
    assert other.save
  end

  test "assignee must belong to the account" do
    issue = issues(:nomethod)
    issue.assignee = users(:outsider)
    assert_not issue.valid?
    assert issue.errors.of_kind?(:assignee, :invalid) || issue.errors[:assignee].any?
  end

  test "accessible by account members only" do
    assert issues(:nomethod).accessible_by?(users(:jo))
    assert_not issues(:nomethod).accessible_by?(users(:outsider))
  end

  test "search text is a lowercased stored column" do
    assert_equal "noMethodError undefined method `price_cents' for nil app/services/cart_total.rb:42 in line_total checkoutscontroller#create".downcase,
      issues(:nomethod).reload.search_text
  end

  test "broadcast stub is callable" do
    assert_nil issues(:nomethod).broadcast_changes_later(created: true)
  end
end
