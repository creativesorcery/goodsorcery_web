require "test_helper"

class Issues::StatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    sign_in_as users(:alex)
  end

  test "renders the stat ribbon frame" do
    get project_issue_stats_path(@project, @issue)

    assert_response :success
    assert_select "turbo-frame##{dom_id(@issue, :stats)} dl" do
      assert_select "dd", "1,284"
      assert_select "dd", "212"
      assert_select "dd", text: /3h ago/
      assert_select "dd", @issue.fingerprint_label
    end
    assert_select "dl.rise", count: 0
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "reflects new counts" do
    @issue.update_columns(events_count: 2_000_001)

    get project_issue_stats_path(@project, @issue)

    assert_select "dd", "2,000,001"
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_issue_stats_path(@project, @issue)

    assert_response :not_found
  end
end
