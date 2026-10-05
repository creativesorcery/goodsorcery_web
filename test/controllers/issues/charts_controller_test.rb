require "test_helper"

class Issues::ChartsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    sign_in_as users(:philip)
  end

  test "renders the 24h chart frame by default" do
    get project_issue_chart_path(@project, @issue)

    assert_response :success
    assert_select "turbo-frame##{dom_id(@issue, :chart)}" do
      assert_select "svg rect", 24
      assert_select "a[aria-current=true]", "24h"
      assert_select "span", "now"
    end
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "switches period" do
    get project_issue_chart_path(@project, issues(:card_error), period: "30d")

    assert_select "turbo-frame svg rect", 30
    assert_select "a[aria-current=true]", "30d"

    get project_issue_chart_path(@project, @issue, period: "7d")

    assert_select "turbo-frame svg rect", 28
    assert_select "a[aria-current=true]", "7d"
  end

  test "an unknown period falls back to 24h" do
    get project_issue_chart_path(@project, @issue, period: "1y")

    assert_select "turbo-frame svg rect", 24
  end

  test "frame reloads do not replay the entrance animation" do
    get project_issue_chart_path(@project, @issue)

    assert_select "section.rise", count: 0
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_issue_chart_path(@project, @issue)

    assert_response :not_found
  end
end
