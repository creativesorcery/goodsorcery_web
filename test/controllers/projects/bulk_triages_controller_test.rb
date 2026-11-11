require "test_helper"

class Projects::BulkTriagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    @list_url = project_issues_url(@project, q: "is:unresolved env:production")
    sign_in_as users(:alex)
  end

  test "resolves the selected issues and returns to the list" do
    ids = [ issues(:nomethod).id, issues(:card_error).id ]

    assert_difference -> { IssueActivity.where(kind: "resolved").count }, 2 do
      post project_bulk_triage_path(@project), params: { issue_ids: ids, triage: "resolve" }, headers: { "Referer" => @list_url }
    end

    assert_redirected_to @list_url
    assert_response :see_other
    assert_equal "Resolved 2 issues.", flash[:notice]
    assert issues(:nomethod).reload.resolved?
    assert issues(:card_error).reload.resolved?
    assert_equal users(:alex), IssueActivity.where(kind: "resolved").last.user
  end

  test "ignores and reopens" do
    post project_bulk_triage_path(@project), params: { issue_ids: [ issues(:regressed).id ], triage: "ignore" }

    assert issues(:regressed).reload.ignored?
    assert_redirected_to project_issues_path(@project)

    post project_bulk_triage_path(@project), params: { issue_ids: [ issues(:regressed).id ], triage: "reopen" }

    assert issues(:regressed).reload.unresolved?
    assert_equal "Reopened 1 issue.", flash[:notice]
  end

  test "assigns to an account member" do
    post project_bulk_triage_path(@project), params: { issue_ids: [ issues(:regressed).id ], assignee_id: users(:jo).id }

    assert_equal users(:jo), issues(:regressed).reload.assignee
    assert_equal "Assigned 1 issue.", flash[:notice]
  end

  test "will not assign someone outside the account" do
    post project_bulk_triage_path(@project), params: { issue_ids: [ issues(:regressed).id ], assignee_id: users(:outsider).id }

    assert_nil issues(:regressed).reload.assignee
    assert_equal "Choose Resolve, Ignore, Reopen or an assignee.", flash[:alert]
  end

  test "ignores ids from other projects and other accounts" do
    ids = [ issues(:billing_timeout).id, issues(:umbrella_issue).id ]

    post project_bulk_triage_path(@project), params: { issue_ids: ids, triage: "resolve" }

    assert issues(:billing_timeout).reload.unresolved?
    assert issues(:umbrella_issue).reload.unresolved?
    assert_equal "Resolved 0 issues.", flash[:notice]
  end

  test "requires a selection and a known action" do
    post project_bulk_triage_path(@project), params: { triage: "resolve" }

    assert_equal "Select at least one issue.", flash[:alert]

    post project_bulk_triage_path(@project), params: { issue_ids: [ issues(:nomethod).id ], triage: "destroy" }

    assert_equal "Choose Resolve, Ignore, Reopen or an assignee.", flash[:alert]
    assert issues(:nomethod).reload.unresolved?
  end

  test "malformed issue_ids are rejected" do
    post project_bulk_triage_path(@project), params: { issue_ids: { "a" => "1" }, triage: "resolve" }

    assert_equal "Select at least one issue.", flash[:alert]
  end

  test "caps the selection at 100 ids" do
    ids = (1..150).to_a + [ issues(:nomethod).id ]

    post project_bulk_triage_path(@project), params: { issue_ids: ids, triage: "resolve" }

    assert issues(:nomethod).reload.unresolved?
  end

  test "does not redirect to another host" do
    post project_bulk_triage_path(@project), params: { issue_ids: [ issues(:nomethod).id ], triage: "resolve" },
      headers: { "Referer" => "https://evil.example/phish" }

    assert_redirected_to project_issues_path(@project)
  end

  test "an outsider gets 404 and changes nothing" do
    sign_in_as users(:outsider)

    post project_bulk_triage_path(@project), params: { issue_ids: [ issues(:nomethod).id ], triage: "resolve" }

    assert_response :not_found
    assert issues(:nomethod).reload.unresolved?
  end

  test "an outsider cannot triage another account's issue through their own project" do
    sign_in_as users(:outsider)

    post project_bulk_triage_path(projects(:umbrella_app)), params: { issue_ids: [ issues(:nomethod).id ], triage: "resolve" }

    assert issues(:nomethod).reload.unresolved?
  end
end
