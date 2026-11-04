require "test_helper"

class UptimeReportTest < ActiveSupport::TestCase
  test "percentages, average response and the 30-day bar in the viewer's zone" do
    report = UptimeReport.new(uptime_monitors(:storefront_home), zone: ActiveSupport::TimeZone["Europe/London"])

    assert_in_delta 100.0 * 143 / 144, report.percentages["24h"]
    assert_equal 210, report.average_response_ms
    assert_equal 30, report.daily_bars.size
    assert_equal ActiveSupport::TimeZone["Europe/London"].today, report.daily_bars.last.first.to_date
    assert_equal 144, report.daily_bars.sum { it[1] }
  end

  test "recent checks are newest first, at most 20" do
    monitor = uptime_monitors(:storefront_api)
    checks = UptimeReport.new(monitor).recent_checks

    assert_equal 12, checks.size
    assert_equal checks.map(&:checked_at).sort.reverse, checks.map(&:checked_at)

    UptimeCheck.insert_all(Array.new(25) { |i| { uptime_monitor_id: monitor.id, checked_at: (20 + i).minutes.ago, status: "up" } })
    assert_equal 20, UptimeReport.new(monitor).recent_checks.size
  end

  test "incidents include the open one, newest first, and drop those older than KEPT_FOR" do
    monitor = uptime_monitors(:storefront_api)
    old = monitor.incidents.create!(started_at: 40.days.ago, resolved_at: 40.days.ago + 5.minutes)
    report = UptimeReport.new(monitor)

    assert_equal [ uptime_incidents(:storefront_api_outage) ], report.incidents
    assert_equal uptime_incidents(:storefront_api_outage), report.open_incident
    assert_not_includes report.incidents, old
  end

  test "an open incident older than KEPT_FOR still shows" do
    incident = uptime_incidents(:storefront_api_outage)
    incident.update_columns(started_at: 40.days.ago)

    assert_equal incident, UptimeReport.new(incident.uptime_monitor).open_incident
  end

  test "up since is the last recovery, else the oldest rollup, and nil unless up" do
    assert_equal uptime_incidents(:storefront_home_timeout).resolved_at, UptimeReport.new(uptime_monitors(:storefront_home)).up_since

    uptime_incidents(:storefront_home_timeout).delete
    oldest = uptime_monitors(:storefront_home).hourly_counts.minimum(:hour)
    assert_equal oldest, UptimeReport.new(uptime_monitors(:storefront_home)).up_since

    assert_nil UptimeReport.new(uptime_monitors(:storefront_api)).up_since
  end

  test "response series covers the last 24 hours" do
    series = UptimeReport.new(uptime_monitors(:storefront_home)).response_series

    assert series.any?
    assert(series.all? { |time, ms| time > 25.hours.ago && ms.between?(200, 220) })
  end
end
