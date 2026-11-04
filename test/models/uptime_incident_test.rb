require "test_helper"

class UptimeIncidentTest < ActiveSupport::TestCase
  test "open, recent and duration" do
    outage = uptime_incidents(:storefront_api_outage)
    resolved = uptime_incidents(:storefront_home_timeout)

    assert_equal [ outage ], UptimeIncident.open.to_a
    assert_predicate outage, :open?
    assert_not resolved.open?
    assert_in_delta 14.minutes, resolved.duration, 1
    assert_equal 12.minutes, outage.duration(now: outage.started_at + 12.minutes)
    assert_operator outage.duration, :>=, 12.minutes - 1
    assert_equal outage, UptimeIncident.recent.first
  end

  test "cause labels" do
    assert_equal "HTTP 503", uptime_incidents(:storefront_api_outage).cause_label
    assert_equal "Timed out after 10 s", uptime_incidents(:storefront_home_timeout).cause_label
  end
end
