require "test_helper"
require_relative "../../test_helpers/uptime_test_helper"

# GOODSORCERY_UPTIME_CONFIRM_DOWN: a failed check needs a second one before
# the monitor goes down. checking_test.rb covers the default (off).
class UptimeMonitor::ConfirmingTest < ActiveSupport::TestCase
  include UptimeTestHelper

  setup do
    freeze_time
    @previous = Rails.configuration.x.uptime.confirm_down
    Rails.configuration.x.uptime.confirm_down = true
  end

  teardown { Rails.configuration.x.uptime.confirm_down = @previous }

  def pending_monitor = uptime_monitors(:billing_checkout)
  def up_monitor = uptime_monitors(:storefront_home)
  def down_monitor = uptime_monitors(:storefront_api)

  test "off by default" do
    with_uptime_confirm_down(@previous) { assert_not_predicate up_monitor, :confirm_down? }
    assert_equal false, @previous
  end

  test "pending → down once: suspected, the status stays, no incident" do
    assert_equal [ nil, "suspected" ], pending_monitor.record_check(down_result("dns_failure"))

    assert_state pending_monitor, status: "pending", down_since: nil, last_error_kind: "dns_failure"
    assert_predicate pending_monitor, :suspected?
    assert_equal 0, pending_monitor.incidents.count
  end

  test "up → down once: suspected, the status stays up, no incident" do
    assert_no_difference -> { UptimeIncident.count } do
      assert_equal [ nil, "suspected" ], up_monitor.record_check(down_result("timeout"))
    end

    assert_state up_monitor, status: "up", down_since: nil, last_error_kind: "timeout", last_checked_at: Time.current
  end

  test "pending → down twice: opens an incident dated from the first failure and alerts monitor_down" do
    pending_monitor.record_check(down_result("dns_failure"))
    incident, kind = pending_monitor.record_check(down_result("dns_failure"), at: 30.seconds.from_now)

    assert_equal "monitor_down", kind
    assert_equal [ Time.current, nil, "dns_failure" ], [ incident.started_at, incident.resolved_at, incident.error_kind ]
    assert_state pending_monitor, status: "down", down_since: Time.current, last_error_kind: "dns_failure"
  end

  test "up → down twice: opens an incident with the confirming check's cause" do
    up_monitor.record_check(down_result("timeout"))
    incident, kind = up_monitor.record_check(down_result("http_status", http_status: 500), at: 30.seconds.from_now)

    assert_equal "monitor_down", kind
    assert_equal [ "http_status", 500, Time.current ], [ incident.error_kind, incident.http_status, incident.started_at ]
    assert_equal incident, up_monitor.open_incident
  end

  test "an up check clears a suspicion: no incident, no alert" do
    up_monitor.record_check(down_result("timeout"))

    assert_nil up_monitor.record_check(up_result(120), at: 30.seconds.from_now)
    assert_state up_monitor, status: "up", down_since: nil, last_error_kind: nil
    assert_not_predicate up_monitor, :suspected?
    assert_equal [ nil, "suspected" ], up_monitor.record_check(down_result("timeout"), at: 10.minutes.from_now)
    assert_equal 0, up_monitor.incidents.where(started_at: Time.current..).count
  end

  test "a suspicion older than two intervals counts as a first failure" do
    up_monitor.record_check(down_result("timeout"))

    later = (2 * up_monitor.interval_minutes).minutes.from_now + 1.second
    assert_equal [ nil, "suspected" ], up_monitor.record_check(down_result("timeout"), at: later)
    assert_state up_monitor, status: "up", last_checked_at: later

    incident, = up_monitor.record_check(down_result("timeout"), at: later + 30.seconds)
    assert_equal later, incident.started_at
  end

  test "a regular check confirms a suspicion when the recheck didn't run" do
    up_monitor.record_check(down_result("timeout"))

    incident, kind = up_monitor.record_check(down_result("timeout"), at: up_monitor.interval_minutes.minutes.from_now)
    assert_equal [ "monitor_down", Time.current ], [ kind, incident.started_at ]
  end

  test "down → down and down → up are unchanged" do
    since = down_monitor.down_since

    assert_nil down_monitor.record_check(down_result("timeout"))
    assert_state down_monitor, status: "down", down_since: since
    assert_equal "monitor_recovered", down_monitor.record_check(up_result, at: 1.minute.from_now).last
  end

  test "a flapping monitor still sends one down and one recovered alert" do
    transitions = 3.times.flat_map do |cycle|
      start = (cycle * 2).minutes.from_now
      [ up_monitor.record_check(down_result("timeout"), at: start),
        up_monitor.record_check(down_result("timeout"), at: start + 30.seconds),
        up_monitor.record_check(up_result, at: start + 1.minute) ]
    end.compact
    incident = up_monitor.incidents.where(started_at: Time.current..).sole

    assert_equal [ [ nil, "suspected" ], [ incident, "monitor_down" ], [ incident, "monitor_recovered" ] ], transitions.uniq
    assert_equal 1, transitions.count { it.last == "monitor_down" }
  end

  test "record_check reads the suspicion under the row lock" do
    pending_monitor.record_check(down_result("timeout"))
    stale = UptimeMonitor.find(pending_monitor.id)
    pending_monitor.record_check(down_result("timeout"), at: 30.seconds.from_now)

    assert_nil stale.record_check(down_result("timeout"), at: 1.minute.from_now), "already down: no second down alert"
    assert_equal 1, pending_monitor.incidents.count
  end

  private
    def assert_state(monitor, **expected)
      monitor.reload
      expected.each do |attribute, value|
        value.nil? ? assert_nil(monitor.public_send(attribute), attribute) : assert_equal(value, monitor.public_send(attribute), attribute)
      end
    end
end
