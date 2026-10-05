require "test_helper"

class Projects::SummariesControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    @project = projects(:storefront)
    sign_in_as users(:philip)
  end

  test "renders the heading and summary strip inside the summary frame" do
    get project_summary_path(@project)

    assert_response :success
    assert_select "turbo-frame##{dom_id(@project, :summary)}" do
      assert_select ".eyebrow", "storefront · all environments"
      assert_select "h1", /3 unresolved/
      assert_select ".segmented a[aria-current=true]", "24h"
      assert_select ".panel", 4
      assert_select ".panel", text: /Events · 24h/
      assert_select ".panel", text: /Regressions\s*1/
      assert_select ".panel svg path", 2
    end
  end

  test "period and environment params" do
    get project_summary_path(@project, period: "1h", env: "production")

    assert_select ".segmented a[aria-current=true]", "1h"
    assert_select ".segmented a[href=?]", project_summary_path(@project, period: "7d", env: "production")
    assert_select ".eyebrow", "storefront · production"
    assert_select ".panel", text: /Events · 1h\s*120/
    assert_select ".text-coral-300", text: /▲ \d+% vs. prev. hour/
  end

  test "unknown period falls back to 24h and bad env is ignored" do
    get project_summary_path(@project, period: "forever", env: "<b>")

    assert_response :success
    assert_select ".segmented a[aria-current=true]", "24h"
    assert_select ".eyebrow", "storefront · all environments"
  end

  test "an outsider gets 404" do
    sign_in_as users(:outsider)

    get project_summary_path(@project)

    assert_response :not_found
  end
end
