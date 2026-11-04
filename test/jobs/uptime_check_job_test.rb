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

  test "skips deleted, paused and monitors checked since the job was enqueued" do
    with_fake_probe do |probe|
      UptimeCheckJob.perform_now(0)
      uptime_monitors(:billing_checkout).update_columns(paused_at: Time.current)
      UptimeCheckJob.perform_now(uptime_monitors(:billing_checkout).id)
      @monitor.update_columns(last_checked_at: 10.seconds.ago)
      UptimeCheckJob.new(@monitor.id).tap { it.enqueued_at = 11.seconds.ago }.perform_now

      assert_equal 0, probe.calls
    end
  end

  test "records the check at the time it started, not when the probe returned" do
    freeze_time

    with_probe(SlowProbe.new(self)) { UptimeCheckJob.perform_now(@monitor.id) }

    assert_equal 40.seconds.ago, @monitor.reload.last_checked_at
    assert_equal 40.seconds.ago, @monitor.checks.recent.first.checked_at
  end

  test "a backed-up queue probes a monitor once, however many claims queued it" do
    UptimeMonitor.update_all(next_check_at: 1.year.from_now)
    @monitor.update_columns(interval_minutes: 1, next_check_at: Time.utc(2026, 11, 3, 12), last_checked_at: Time.utc(2026, 11, 3, 11, 59))
    travel_to(Time.utc(2026, 11, 3, 12, 0, 1)) { UptimeSchedule.enqueue_due }
    travel_to(Time.utc(2026, 11, 3, 12, 1, 2)) { UptimeSchedule.enqueue_due }
    assert_enqueued_jobs 2, only: UptimeCheckJob

    first, second = enqueued_jobs.map { |payload| UptimeCheckJob.deserialize(payload) }

    with_fake_probe(up_result, up_result) do |probe|
      assert_difference -> { @monitor.checks.count }, 1 do
        travel_to(Time.utc(2026, 11, 3, 12, 3)) { first.perform_now }
        travel_to(Time.utc(2026, 11, 3, 12, 4)) { second.perform_now }
      end
      assert_equal 1, probe.calls
    end
  end

  test "of two jobs probing at once, only the first to record keeps its check" do
    enqueued_at = 1.second.ago
    @monitor.record_check(up_result, at: Time.current)

    assert_no_difference -> { @monitor.checks.count } do
      assert_nil @monitor.record_check(down_result, at: Time.current, unless_checked_since: enqueued_at)
    end
    assert_predicate @monitor.reload, :up?
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
    # Fails after 20 seconds of (test) time, so a check and its retry take 40.
    class SlowProbe
      def initialize(test) = @test = test

      def check
        @test.travel 20.seconds
        UptimeProbe::Result.down("timeout")
      end
    end

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
