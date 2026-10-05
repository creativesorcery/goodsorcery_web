require "test_helper"

class Issues::ResolutionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    sign_in_as users(:philip)
  end

  test "resolves an issue and records who did it" do
    issue = issues(:nomethod)

    assert_difference -> { issue.activities.resolved.count }, 1 do
      post project_issue_resolution_path(@project, issue)
    end

    assert_redirected_to project_issue_path(@project, issue)
    assert_equal 303, response.status
    assert issue.reload.resolved?
    assert_equal users(:philip), issue.activities.resolved.last.user
  end

  test "reopens a resolved issue" do
    issue = issues(:resolved_issue)

    delete project_issue_resolution_path(@project, issue)

    assert_redirected_to project_issue_path(@project, issue)
    assert issue.reload.unresolved?
    assert issue.activities.reopened.exists?
  end

  test "outsiders get 404 and change nothing" do
    sign_in_as users(:outsider)
    issue = issues(:nomethod)

    post project_issue_resolution_path(@project, issue)

    assert_response :not_found
    assert issue.reload.unresolved?
  end

  test "outsiders cannot reopen either" do
    sign_in_as users(:outsider)

    delete project_issue_resolution_path(@project, issues(:resolved_issue))

    assert_response :not_found
    assert issues(:resolved_issue).reload.resolved?
  end
end
