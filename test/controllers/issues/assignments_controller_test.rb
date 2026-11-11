require "test_helper"

class Issues::AssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    sign_in_as users(:alex)
  end

  test "assigns to an account member" do
    patch project_issue_assignment_path(@project, @issue), params: { assignee_id: users(:jo).id }

    assert_redirected_to project_issue_path(@project, @issue)
    assert_equal users(:jo), @issue.reload.assignee
    assert_equal users(:jo), @issue.activities.assigned.recent.first.subject_user
  end

  test "cannot assign someone outside the account" do
    patch project_issue_assignment_path(@project, @issue), params: { assignee_id: users(:outsider).id }

    assert_response :not_found
    assert_equal users(:alex), @issue.reload.assignee
  end

  test "an assignee is required" do
    patch project_issue_assignment_path(@project, @issue)

    assert_response :bad_request
  end

  test "unassigns" do
    delete project_issue_assignment_path(@project, @issue)

    assert_redirected_to project_issue_path(@project, @issue)
    assert_nil @issue.reload.assignee
    assert @issue.activities.unassigned.exists?
  end

  test "outsiders get 404 and change nothing" do
    sign_in_as users(:outsider)

    patch project_issue_assignment_path(@project, @issue), params: { assignee_id: users(:outsider).id }
    assert_response :not_found

    delete project_issue_assignment_path(@project, @issue)
    assert_response :not_found

    assert_equal users(:alex), @issue.reload.assignee
  end
end
