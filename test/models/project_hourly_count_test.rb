require "test_helper"

class ProjectHourlyCountTest < ActiveSupport::TestCase
  setup { @ids = projects(:storefront, :billing, :marketing).map(&:id) }

  test "daily series for many projects in one query" do
    result = nil
    assert_queries_count(1) { result = ProjectHourlyCount.daily_series(@ids) }

    assert_equal 14, result[projects(:storefront).id].size
    assert_equal [ 0 ] * 14, result[projects(:marketing).id]
    today = ProjectHourlyCount.where(project: projects(:storefront), hour: Time.current.utc.beginning_of_day..).sum(:count)
    assert_equal today, result[projects(:storefront).id].last
  end

  test "hourly totals sum environments" do
    result = ProjectHourlyCount.hourly_totals(@ids)

    assert_equal 24, result[projects(:storefront).id].size
    assert_equal 126, result[projects(:storefront).id].last
    assert_equal [ 8 ] * 24, result[projects(:billing).id]
  end

  test "total over a window, optionally per environment" do
    from = Time.current.utc.beginning_of_hour
    to = from + 1.hour

    assert_equal 126, ProjectHourlyCount.total(projects(:storefront), from:, to:)
    assert_equal 6, ProjectHourlyCount.total(projects(:storefront), from:, to:, environment: "staging")
  end

  test "series for one project" do
    from = Time.current.utc.beginning_of_hour - 2.hours
    values = ProjectHourlyCount.series(projects(:storefront), from:, buckets: 3, environment: "production")

    assert_equal [ 42, 41, 120 ], values
  end
end
