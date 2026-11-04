require "test_helper"
require_relative "../../test_helpers/uptime_test_helper"

class UptimeMonitor::CheckingTest < ActiveSupport::TestCase
  include UptimeTestHelper

  setup { freeze_time }

  def pending_monitor = uptime_monitors(:billing_checkout)
  def up_monitor = uptime_monitors(:storefront_home)
  def down_monitor = uptime_monitors(:storefront_api)

  test "run_check keeps an up result without retrying" do
    probe = FakeProbe.new([ up_result ])

    assert_predicate up_monitor.run_check(probe), :up?
    assert_equal 1, probe.calls
  end

  test "run_check retries a failure once at once and keeps the second result" do
    probe = FakeProbe.new([ down_result("timeout"), up_result(300) ])

    result = up_monitor.run_check(probe)

    assert_equal [ "up", 300 ], [ result.status, result.response_time_ms ]
    assert_equal 2, probe.calls
  end

  test "run_check reports down when the retry fails too" do
    probe = FakeProbe.new([ down_result("timeout"), down_result("http_status", http_status: 502) ])

    assert_equal [ "down", "http_status", 502 ], up_monitor.run_check(probe).then { [ it.status, it.error_kind, it.http_status ] }
  end

  test "run_check never retries a blocked address" do
    probe = FakeProbe.new([ down_result("blocked_address") ])

    assert_equal "blocked_address", up_monitor.run_check(probe).error_kind
    assert_equal 1, probe.calls
  end

  test "pending → up: no incident, no alert" do
    assert_nil pending_monitor.record_check(up_result(150))

    assert_state pending_monitor, status: "up", down_since: nil, last_response_time_ms: 150, last_http_status: 200
    assert_equal 0, pending_monitor.incidents.count
  end

  test "pending → down: opens an incident and alerts monitor_down" do
    incident, kind = pending_monitor.record_check(down_result("dns_failure"))

    assert_equal "monitor_down", kind
    assert_equal [ Time.current, nil, "dns_failure" ], [ incident.started_at, incident.resolved_at, incident.error_kind ]
    assert_state pending_monitor, status: "down", down_since: Time.current, last_error_kind: "dns_failure"
  end

  test "up → down: opens an incident with the cause" do
    incident, kind = up_monitor.record_check(down_result("http_status", http_status: 500))

    assert_equal "monitor_down", kind
    assert_equal [ "http_status", 500 ], [ incident.error_kind, incident.http_status ]
    assert_predicate incident, :open?
    assert_equal incident, up_monitor.open_incident
  end

  test "down → down: the incident stays open and down_since is kept" do
    since = down_monitor.down_since

    assert_no_difference -> { UptimeIncident.count } do
      assert_nil down_monitor.record_check(down_result("timeout"))
    end
    assert_state down_monitor, status: "down", down_since: since, last_error_kind: "timeout"
    assert_predicate uptime_incidents(:storefront_api_outage).reload, :open?
  end

  test "down → up: resolves the open incident and alerts monitor_recovered" do
    incident, kind = down_monitor.record_check(up_result)

    assert_equal [ uptime_incidents(:storefront_api_outage), "monitor_recovered" ], [ incident, kind ]
    assert_equal Time.current, incident.reload.resolved_at
    assert_state down_monitor, status: "up", down_since: nil, last_error_kind: nil
  end

  test "up → up: nothing but the check" do
    assert_nil up_monitor.record_check(up_result)

    assert_state up_monitor, status: "up", last_checked_at: Time.current
  end

  test "records the check row and the hourly rollup, without the URL" do
    UptimeHourlyCount.where(uptime_monitor: pending_monitor).delete_all

    pending_monitor.record_check(up_result(100))
    pending_monitor.record_check(down_result("timeout"), at: 1.second.from_now)
    pending_monitor.record_check(up_result(300), at: 2.seconds.from_now)

    hour = UptimeHourlyCount.find_by!(uptime_monitor: pending_monitor, hour: TimeSeries.align(Time.current, 1.hour))
    assert_equal [ 3, 2, 400 ], [ hour.checks_count, hour.up_count, hour.response_time_ms_sum ]
    check = pending_monitor.checks.recent.second
    assert_equal [ "down", "timeout", nil ], [ check.status, check.error_kind, check.response_time_ms ]
    assert_equal %w[checked_at error_kind http_status id response_time_ms status uptime_monitor_id], UptimeCheck.column_names.sort
  end

  test "a monitor whose status says up but has an open incident doesn't open a second one" do
    down_monitor.update_columns(status: "up", down_since: nil)

    assert_no_difference -> { UptimeIncident.count } do
      assert_nil down_monitor.record_check(down_result("timeout"))
    end
    assert_state down_monitor, status: "down"
  end

  test "the database allows one open incident per monitor" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      UptimeIncident.create!(uptime_monitor: down_monitor, started_at: Time.current)
    end
    assert UptimeIncident.create!(uptime_monitor: down_monitor, started_at: 1.day.ago, resolved_at: 23.hours.ago)
  end

  test "record_check reads the current state under the row lock" do
    stale = UptimeMonitor.find(pending_monitor.id)
    pending_monitor.record_check(down_result("timeout"))

    assert_nil stale.record_check(down_result("timeout")), "already down: no second down alert"
    assert_equal 1, pending_monitor.incidents.count
  end

  test "check_soon gates repeated requests for RECHECK_GAP" do
    with_memory_cache do
      monitor = uptime_monitors(:storefront_home)
      monitor.update_columns(last_checked_at: 1.minute.ago)

      assert monitor.check_soon
      assert_not monitor.check_soon
      travel UptimeMonitor::RECHECK_GAP + 1.second
      assert monitor.check_soon
    end
  end

  test "check_soon refuses a monitor checked recently or paused" do
    with_memory_cache do
      assert_not uptime_monitors(:storefront_home).tap { it.update_columns(last_checked_at: 10.seconds.ago) }.check_soon
      assert_not uptime_monitors(:billing_checkout).tap { it.update_columns(paused_at: Time.current) }.check_soon
    end
  end

  private
    def assert_state(monitor, **expected)
      monitor.reload
      expected.each do |attribute, value|
        value.nil? ? assert_nil(monitor.public_send(attribute), attribute) : assert_equal(value, monitor.public_send(attribute), attribute)
      end
    end

    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end
end
