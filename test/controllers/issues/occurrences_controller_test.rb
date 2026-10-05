require "test_helper"

class Issues::OccurrencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    sign_in_as users(:philip)
  end

  test "shows an occurrence by uuid" do
    get project_issue_occurrence_path(@project, @issue, occurrences(:nomethod_oldest))

    assert_response :success
    assert_select "turbo-frame#occurrence"
    assert_select "span.font-mono.text-iris-300", "1"
    assert_select "span", text: /· oldest/
    assert_select "#context-request span", text: "11111111-1e0f-4b8e-a2d1-55f0c8e1b0aa"
    assert_select "a[aria-label='Newer occurrence'][href=?]", project_issue_occurrence_path(@project, @issue, occurrences(:nomethod_latest))
    assert_select "span[aria-label='Older occurrence'][aria-disabled=true]"
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "latest, oldest and random shortcuts" do
    get project_issue_occurrence_path(@project, @issue, "latest")
    assert_select "#context-request span", text: "7d4c2a91-1e0f-4b8e-a2d1-55f0c8e1b0aa"
    assert_select "a[aria-current=true]", "Latest"

    get project_issue_occurrence_path(@project, @issue, "oldest")
    assert_select "#context-request span", text: "11111111-1e0f-4b8e-a2d1-55f0c8e1b0aa"
    assert_select "a[aria-current=true]", "Oldest"

    get project_issue_occurrence_path(@project, @issue, "random")
    assert_response :success
    assert_select "a[aria-current=true]", "Random"
  end

  test "a frame request still renders the occurrence frame" do
    get project_issue_occurrence_path(@project, @issue, "oldest"), headers: { "Turbo-Frame" => "occurrence" }

    assert_response :success
    assert_select "turbo-frame#occurrence"
  end

  test "an unknown uuid or a malformed id is a 404" do
    get project_issue_occurrence_path(@project, @issue, "0192f7a4-0000-7000-8000-000000000000")
    assert_response :not_found

    get project_issue_occurrence_path(@project, @issue, "not-a-uuid")
    assert_response :not_found
  end

  test "another issue's occurrence is a 404" do
    get project_issue_occurrence_path(@project, @issue, occurrences(:regressed_latest))

    assert_response :not_found
  end

  test "another account's occurrence is a 404, even through the right issue path" do
    umbrella = projects(:umbrella_app)

    get project_issue_occurrence_path(umbrella, issues(:umbrella_issue), occurrences(:umbrella_occurrence))

    assert_response :not_found
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_issue_occurrence_path(@project, @issue, occurrences(:nomethod_latest))

    assert_response :not_found
  end

  test "requires sign in" do
    sign_out

    get project_issue_occurrence_path(@project, @issue, "latest")

    assert_redirected_to new_session_path
  end
end
