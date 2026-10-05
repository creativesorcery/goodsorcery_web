require "test_helper"

class Issues::IgnoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    sign_in_as users(:philip)
  end

  test "ignores an issue" do
    issue = issues(:nomethod)

    post project_issue_ignore_path(@project, issue)

    assert_redirected_to project_issue_path(@project, issue)
    assert issue.reload.ignored?
    assert issue.activities.ignored.exists?
  end

  test "stops ignoring, which reopens" do
    issue = issues(:ignored_issue)

    delete project_issue_ignore_path(@project, issue)

    assert_redirected_to project_issue_path(@project, issue)
    assert issue.reload.unresolved?
  end

  test "outsiders get 404 and change nothing" do
    sign_in_as users(:outsider)

    post project_issue_ignore_path(@project, issues(:nomethod))
    assert_response :not_found

    delete project_issue_ignore_path(@project, issues(:ignored_issue))
    assert_response :not_found

    assert issues(:nomethod).reload.unresolved?
    assert issues(:ignored_issue).reload.ignored?
  end
end
