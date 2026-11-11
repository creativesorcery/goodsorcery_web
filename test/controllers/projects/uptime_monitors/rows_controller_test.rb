require "test_helper"
require_relative "../../../test_helpers/uptime_test_helper"

class Projects::UptimeMonitors::RowsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier, UptimeTestHelper

  setup do
    @project = projects(:storefront)
    @monitor = uptime_monitors(:storefront_home)
    sign_in_as users(:alex)
  end

  test "renders one row in its frame, without the URL's path or query" do
    get project_uptime_monitor_row_path(@project, @monitor)

    assert_response :success
    assert_select "turbo-frame##{dom_id(@monitor, :row)}[target=_top]" do
      assert_select ".chip-mint", "Up"
      assert_select "a[href=?]", project_uptime_monitor_path(@project, @monitor), text: "Storefront home"
      assert_select "svg rect", 24
    end
    assert_no_match SECRET, response.body
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "signed out, outsiders and other apps' monitors get nothing" do
    sign_out
    get project_uptime_monitor_row_path(@project, @monitor)
    assert_redirected_to new_session_path

    sign_in_as users(:outsider)
    get project_uptime_monitor_row_path(@project, @monitor)
    assert_response :not_found

    sign_in_as users(:alex)
    get project_uptime_monitor_row_path(@project, uptime_monitors(:billing_checkout))
    assert_response :not_found
  end
end
