require "test_helper"

class Projects::UptimeMonitors::ChecksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @project = projects(:storefront)
    @monitor = uptime_monitors(:storefront_home)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    sign_in_as users(:philip)
  end

  teardown { Rails.cache = @original_cache }

  test "Check now enqueues a check with the monitor's id only" do
    assert_enqueued_with job: UptimeCheckJob, args: [ @monitor.id ], queue: "uptime" do
      post project_uptime_monitor_check_path(@project, @monitor)
    end

    assert_redirected_to project_uptime_monitor_path(@project, @monitor)
    assert_equal "Checking Storefront home now…", flash[:notice]
  end

  test "a second Check now within 30 seconds is refused" do
    post project_uptime_monitor_check_path(@project, @monitor)

    assert_no_enqueued_jobs only: UptimeCheckJob do
      post project_uptime_monitor_check_path(@project, @monitor)
    end
    assert_equal "Checked less than 30 seconds ago.", flash[:alert]

    travel UptimeMonitor::RECHECK_GAP + 1.second
    assert_enqueued_jobs 1, only: UptimeCheckJob do
      post project_uptime_monitor_check_path(@project, @monitor)
    end
  end

  test "hosted, Check now can't run more often than the account's shortest interval" do
    with_hosted_mode do
      post project_uptime_monitor_check_path(@project, @monitor)
      @monitor.update_columns(last_checked_at: Time.current)

      travel 31.seconds
      assert_no_enqueued_jobs only: UptimeCheckJob do
        post project_uptime_monitor_check_path(@project, @monitor)
      end
      assert_equal "Checked less than 10 minutes ago.", flash[:alert]

      travel 10.minutes
      assert_enqueued_jobs 1, only: UptimeCheckJob do
        post project_uptime_monitor_check_path(@project, @monitor)
      end
    end
  end

  test "a monitor checked in the last 30 seconds is refused" do
    @monitor.update_columns(last_checked_at: 10.seconds.ago)

    assert_no_enqueued_jobs only: UptimeCheckJob do
      post project_uptime_monitor_check_path(@project, @monitor)
    end
    assert_equal "Checked less than 30 seconds ago.", flash[:alert]
  end

  test "a paused monitor is refused" do
    @monitor.update_columns(paused_at: Time.current)

    assert_no_enqueued_jobs only: UptimeCheckJob do
      post project_uptime_monitor_check_path(@project, @monitor)
    end
    assert_equal "Storefront home is paused, so it isn't checked.", flash[:alert]
  end

  test "Check now is rate limited to 10 a minute per user" do
    monitors = [ @monitor, uptime_monitors(:storefront_api) ]
    10.times { |i| post project_uptime_monitor_check_path(@project, monitors[i % 2]) }

    assert_no_enqueued_jobs only: UptimeCheckJob do
      travel UptimeMonitor::RECHECK_GAP + 1.second
      post project_uptime_monitor_check_path(@project, @monitor)
    end
    assert_equal "Too many checks. Try again in a minute.", flash[:alert]

    sign_in_as users(:jo)
    assert_enqueued_jobs 1, only: UptimeCheckJob do
      post project_uptime_monitor_check_path(@project, @monitor)
    end
  end

  test "signed out, outsiders and other apps' monitors can't check" do
    sign_out
    post project_uptime_monitor_check_path(@project, @monitor)
    assert_redirected_to new_session_path

    sign_in_as users(:outsider)
    post project_uptime_monitor_check_path(@project, @monitor)
    assert_response :not_found

    sign_in_as users(:philip)
    post project_uptime_monitor_check_path(@project, uptime_monitors(:billing_checkout))
    assert_response :not_found
    assert_no_enqueued_jobs only: UptimeCheckJob
  end
end
