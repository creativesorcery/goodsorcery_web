require "test_helper"
require_relative "../test_helpers/uptime_test_helper"

class UptimeCheckJobTest < ActiveJob::TestCase
  include UptimeTestHelper

  setup { @monitor = uptime_monitors(:storefront_home).tap { it.update_columns(last_checked_at: 5.minutes.ago) } }

  test "runs on the uptime queue with the monitor id only" do
    assert_equal "uptime", UptimeCheckJob.new.queue_name
    assert_enqueued_with(job: UptimeCheckJob, args: [ @monitor.id ]) { UptimeCheckJob.perform_later(@monitor.id) }
    assert_not_includes enqueued_jobs.inspect, SECRET
  end

  test "checks, records and broadcasts" do
    calls = hook_calls do
      with_fake_probe(up_result(180)) { UptimeCheckJob.perform_now(@monitor.id) }
    end

    assert_equal [ [ :broadcast_checked, @monitor.id ] ], calls
    assert_equal [ "up", 180 ], @monitor.reload.then { [ it.status, it.last_response_time_ms ] }
    assert_equal 180, @monitor.checks.recent.first.response_time_ms
  end

  test "hands a transition to the alert hook after the record commits" do
    calls = hook_calls do
      with_fake_probe(down_result("timeout"), down_result("timeout")) { UptimeCheckJob.perform_now(@monitor.id) }
    end
    incident = @monitor.open_incident

    assert_equal [ [ :alert_later, incident.id, "monitor_down" ], [ :broadcast_checked, @monitor.id ] ], calls
  end

  test "skips deleted, paused and recently checked monitors" do
    with_fake_probe do |probe|
      UptimeCheckJob.perform_now(0)
      uptime_monitors(:billing_checkout).update_columns(paused_at: Time.current)
      UptimeCheckJob.perform_now(uptime_monitors(:billing_checkout).id)
      @monitor.update_columns(last_checked_at: 10.seconds.ago)
      UptimeCheckJob.perform_now(@monitor.id)

      assert_equal 0, probe.calls
    end
  end

  test "a monitor deleted during its check is discarded" do
    monitor_id = @monitor.id
    probe = Object.new
    probe.define_singleton_method(:check) do
      UptimeMonitor.where(id: monitor_id).delete_all
      UptimeProbe::Result.up(response_time_ms: 90, http_status: 200)
    end

    with_probe(probe) { assert_nothing_raised { UptimeCheckJob.perform_now(monitor_id) } }
    assert_equal 0, UptimeCheck.where(uptime_monitor_id: monitor_id).count
  end

  test "the monitor URL never reaches the log, passing or failing" do
    log = capture_log do
      with_fake_probe(up_result) { UptimeCheckJob.perform_now(@monitor.id) }
      @monitor.update_columns(last_checked_at: 5.minutes.ago)
      with_fake_probe(down_result("tls_error"), down_result("tls_error")) { UptimeCheckJob.perform_now(@monitor.id) }
    end

    assert_includes log, "uptime_checks"
    assert_not_includes log, SECRET
    assert_not_includes log, "storefront.example"
  end

  private
    # Records the calls to the hooks slices 3 and 4 implement.
    def hook_calls
      calls = []
      UptimeMonitor.define_method(:alert_later) { |incident, kind| calls << [ :alert_later, incident.id, kind ] }
      UptimeMonitor.define_method(:broadcast_checked) { calls << [ :broadcast_checked, id ] }
      yield
      calls
    ensure
      UptimeMonitor.remove_method(:alert_later, :broadcast_checked)
    end
end
