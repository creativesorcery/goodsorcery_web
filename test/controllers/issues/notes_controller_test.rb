require "test_helper"

class Issues::NotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    sign_in_as users(:alex)
  end

  test "adds a note and streams it into the activity feed" do
    assert_difference -> { @issue.activities.note.count }, 1 do
      post project_issue_notes_path(@project, @issue), params: { note: { body: "Deploying <b>a fix</b> now" } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=prepend][target=?]", dom_id(@issue, :activities)
    assert_select "turbo-stream[action=replace][target=?]", dom_id(@issue, :note_form)
    assert_includes response.body, "Deploying &lt;b&gt;a fix&lt;/b&gt; now"

    note = @issue.activities.note.recent.first
    assert_equal users(:alex), note.user
    assert_equal "Deploying <b>a fix</b> now", note.body
  end

  test "stores the body encrypted" do
    post project_issue_notes_path(@project, @issue), params: { note: { body: "secret plan" } }, as: :turbo_stream

    raw = IssueActivity.connection.select_value("SELECT body FROM issue_activities ORDER BY id DESC LIMIT 1")
    assert_not_includes raw, "secret plan"
  end

  test "a blank note re-renders the form with an error" do
    assert_no_difference -> { IssueActivity.count } do
      post project_issue_notes_path(@project, @issue), params: { note: { body: "   " } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=prepend]", count: 0
    assert_select "turbo-stream[action=replace][target=?]", dom_id(@issue, :note_form)
  end

  test "html fallback redirects to the issue" do
    post project_issue_notes_path(@project, @issue), params: { note: { body: "Looking into it" } }

    assert_redirected_to project_issue_path(@project, @issue)
  end

  test "outsiders get 404 and add nothing" do
    sign_in_as users(:outsider)

    assert_no_difference -> { IssueActivity.count } do
      post project_issue_notes_path(@project, @issue), params: { note: { body: "hi" } }, as: :turbo_stream
    end

    assert_response :not_found
  end
end
