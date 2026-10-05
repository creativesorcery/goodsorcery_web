require "test_helper"

class Issue::TriageTest < ActiveSupport::TestCase
  setup { @philip = users(:philip) }

  test "resolve sets status, timestamp, clears regression and records activity" do
    issue = issues(:regressed)

    assert_difference -> { issue.activities.resolved.count } => 1 do
      issue.resolve(by: @philip)
    end

    issue.reload
    assert issue.resolved?
    assert issue.resolved_at
    assert_nil issue.regressed_at
    assert_equal @philip, issue.activities.recent.first.user
  end

  test "triage expires the cached unresolved counts at once" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    project = projects(:storefront)
    before = project.cached_unresolved_count
    staging = project.cached_unresolved_count("staging")

    issues(:nomethod).resolve(by: @philip)
    assert_equal before - 1, project.cached_unresolved_count

    Issue.where(id: issues(:regressed).id).resolve_all(by: @philip)
    assert_equal before - 2, project.cached_unresolved_count
    assert_operator project.cached_unresolved_count("staging"), :<=, staging
  ensure
    Rails.cache = original
  end

  test "resolving twice records one activity" do
    issue = issues(:nomethod)
    assert_difference -> { issue.activities.count } => 1 do
      issue.resolve(by: @philip)
      issue.resolve(by: @philip)
    end
  end

  test "ignore and reopen" do
    issue = issues(:nomethod)

    issue.ignore(by: @philip)
    assert issue.reload.ignored?

    issue.reopen(by: @philip)
    assert issue.reload.unresolved?
    assert_equal %w[reopened ignored], issue.activities.recent.limit(2).pluck(:kind)
  end

  test "reopen clears resolved_at" do
    issue = issues(:resolved_issue)
    issue.reopen(by: nil)

    assert issue.reload.unresolved?
    assert_nil issue.resolved_at
    assert_nil issue.activities.reopened.sole.user
  end

  test "assign and unassign record the subject user" do
    issue = issues(:regressed)

    issue.assign(users(:jo), by: @philip)
    assert_equal users(:jo), issue.reload.assignee
    assert_equal users(:jo), issue.activities.assigned.sole.subject_user

    issue.unassign(by: @philip)
    assert_nil issue.reload.assignee
    assert_equal users(:jo), issue.activities.unassigned.sole.subject_user
  end

  test "assigning a non-member fails" do
    assert_raises(ActiveRecord::RecordInvalid) { issues(:regressed).assign(users(:outsider), by: @philip) }
    assert_nil issues(:regressed).reload.assignee
  end

  test "resolve_all updates the relation in bulk and logs one activity per changed issue" do
    scope = projects(:storefront).issues.where(id: issues(:nomethod, :regressed, :resolved_issue).map(&:id))

    ids = nil
    assert_difference -> { IssueActivity.resolved.count } => 2 do
      ids = scope.resolve_all(by: @philip)
    end

    assert_equal issues(:nomethod, :regressed).map(&:id).sort, ids.sort
    assert scope.reload.all?(&:resolved?)
    assert_nil issues(:regressed).reload.regressed_at
  end

  test "bulk triage never escapes the relation" do
    projects(:storefront).issues.where(id: issues(:umbrella_issue).id).ignore_all(by: @philip)
    assert issues(:umbrella_issue).reload.unresolved?
  end

  test "bulk triage is capped at 100 issues" do
    assert_equal 100, Issue::Triage::BULK_LIMIT
  end

  test "ignore_all and reopen_all" do
    scope = projects(:storefront).issues.where(id: [ issues(:nomethod).id, issues(:ignored_issue).id ])

    assert_equal [ issues(:nomethod).id ], scope.ignore_all(by: @philip)
    assert scope.reload.all?(&:ignored?)

    assert_equal 2, scope.reopen_all(by: @philip).size
    assert scope.reload.all?(&:unresolved?)
  end

  test "assign_all only assigns account members" do
    scope = projects(:storefront).issues.where(id: [ issues(:nomethod).id, issues(:regressed).id ])

    assert_equal [ issues(:regressed).id ], scope.assign_all(users(:philip), by: @philip)
    assert_equal users(:philip), issues(:regressed).reload.assignee
    assert_raises(ArgumentError) { scope.assign_all(users(:outsider), by: @philip) }
  end

  test "bulk triage on an empty relation is a no-op" do
    assert_no_difference -> { IssueActivity.count } do
      assert_empty projects(:marketing).issues.resolve_all(by: @philip)
    end
  end
end
