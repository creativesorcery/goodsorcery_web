require "test_helper"

class UptimeHourlyCountTest < ActiveSupport::TestCase
  def ids = [ uptime_monitors(:storefront_home).id, uptime_monitors(:storefront_api).id, uptime_monitors(:billing_checkout).id ]

  test "uptime percentages per window in one query" do
    home, api, billing = ids
    percentages = assert_queries_count(1) { UptimeHourlyCount.uptime_percentages(ids) }

    assert_in_delta 100.0 * 143 / 144, percentages[home]["24h"], 0.001
    assert_in_delta 100.0 * 143 / 144, percentages[home]["30d"], 0.001
    assert_in_delta 100.0 * 285 / 288, percentages[api]["7d"], 0.001
    assert_equal({ "24h" => nil, "7d" => nil, "30d" => nil }, percentages[billing])
  end

  test "older hours count in the longer windows only" do
    home = uptime_monitors(:storefront_home)
    UptimeHourlyCount.create!(uptime_monitor: home, hour: TimeSeries.align(3.days.ago, 1.hour), checks_count: 6, up_count: 0)
    UptimeHourlyCount.create!(uptime_monitor: home, hour: TimeSeries.align(31.days.ago, 1.hour), checks_count: 6, up_count: 0)

    percentages = UptimeHourlyCount.uptime_percentages([ home.id ])[home.id]

    assert_in_delta 100.0 * 143 / 144, percentages["24h"], 0.001
    assert_in_delta 100.0 * 143 / 150, percentages["7d"], 0.001
    assert_in_delta 100.0 * 143 / 150, percentages["30d"], 0.001
  end

  test "hourly bars are zero-filled, oldest first, in one query" do
    home, _, billing = ids
    bars = assert_queries_count(1) { UptimeHourlyCount.hourly_bars(ids) }

    assert_equal 24, bars[home].size
    assert_equal [ TimeSeries.align(Time.current, 1.hour), 6, 6 ], bars[home].last
    assert_equal [ 6, 5 ], bars[home][-6].drop(1)
    assert bars[billing].all? { |_, checks, up| checks.zero? && up.zero? }
  end

  test "daily bars use the viewer's days" do
    zone = ActiveSupport::TimeZone["Pacific/Auckland"]
    bars = UptimeHourlyCount.daily_bars(uptime_monitors(:storefront_home), zone:)

    assert_equal 30, bars.size
    assert_equal zone.today.in_time_zone(zone), bars.last.first
    assert_equal 144, bars.sum { |_, checks, _| checks }
    assert_equal 143, bars.sum { |_, _, up| up }
  end

  test "average response time of up checks" do
    home, api, billing = ids
    averages = assert_queries_count(1) { UptimeHourlyCount.average_response_ms(ids, since: 24.hours.ago) }

    assert_equal({ home => 210, api => 95, billing => nil }, averages)
  end
end
