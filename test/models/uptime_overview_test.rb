require "test_helper"

class UptimeOverviewTest < ActiveSupport::TestCase
  setup { @project = projects(:storefront) }

  test "rows pair each monitor with its uptime percentages and 24 hourly bars" do
    rows = UptimeOverview.new(@project.uptime_monitors.order(:name)).rows

    assert_equal [ "Storefront API", "Storefront home" ], rows.map { it.monitor.name }
    home = rows.last
    assert_equal %w[24h 7d 30d], home.percentages.keys
    assert_in_delta 100.0 * 143 / 144, home.percentages["24h"]
    assert_equal 24, home.bars.size
    assert_equal [ 6, 6 ], home.bars.last.drop(1)
  end

  test "costs 3 queries however many monitors there are" do
    one = UptimeOverview.new(@project.uptime_monitors.where(id: uptime_monitors(:storefront_home)))
    assert_queries_count(3) { one.rows }

    3.times { |i| @project.uptime_monitors.create!(name: "Extra #{i}", url: "https://extra#{i}.example/") }
    many = UptimeOverview.new(@project.uptime_monitors.order(:name))
    assert_queries_count(3) { assert_equal 5, many.size }
  end

  test "an app without monitors costs one query and is empty" do
    overview = UptimeOverview.new(projects(:marketing).uptime_monitors)

    assert_queries_count(1) { assert overview.empty? }
    assert_equal 0, overview.size
  end
end
