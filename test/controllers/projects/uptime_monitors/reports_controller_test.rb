require "test_helper"

class Projects::UptimeMonitors::ReportsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    @project = projects(:storefront)
    @monitor = uptime_monitors(:storefront_api)
    sign_in_as users(:alex)
  end

  test "renders the report in its frame" do
    get project_uptime_monitor_report_path(@project, @monitor)

    assert_response :success
    assert_select "turbo-frame##{dom_id(@monitor, :report)}[target=_top]" do
      assert_select "h1", "Storefront API"
      assert_select ".chip-coral", /Down for 12 min/
      assert_select "dt", "Down since"
      assert_select "section[aria-labelledby=uptime_checks_heading] li", 12
    end
    assert_select ".rise", count: 0
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "signed out, outsiders and other apps' monitors get nothing" do
    sign_out
    get project_uptime_monitor_report_path(@project, @monitor)
    assert_redirected_to new_session_path

    sign_in_as users(:outsider)
    get project_uptime_monitor_report_path(@project, @monitor)
    assert_response :not_found

    sign_in_as users(:alex)
    get project_uptime_monitor_report_path(@project, uptime_monitors(:billing_checkout))
    assert_response :not_found
  end
end
