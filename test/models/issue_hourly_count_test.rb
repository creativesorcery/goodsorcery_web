require "test_helper"

class IssueHourlyCountTest < ActiveSupport::TestCase
  test "histograms returns zero-filled 24 hour series for every requested issue in one query" do
    ids = issues(:nomethod, :card_error, :resolved_issue).map(&:id)

    result = nil
    assert_queries_count(1) { result = IssueHourlyCount.histograms(ids) }

    assert_equal ids.sort, result.keys.sort
    assert_equal [ 2, 3, 5, 8, 13, 21, 34, 55, 89, 120, 140, 90, 70, 60, 50, 40, 60, 80, 100, 90, 70, 50, 40, 32 ],
      result[issues(:nomethod).id]
    assert_equal [ 0 ] * 24, result[issues(:resolved_issue).id]
    assert_equal 5, result[issues(:card_error).id].last
  end

  test "histograms with a custom window" do
    assert_equal [ 50, 40, 32 ], IssueHourlyCount.histograms([ issues(:nomethod).id ], hours: 3)[issues(:nomethod).id]
  end

  test "24h series is hourly and ends in the current hour" do
    points = IssueHourlyCount.series(issues(:nomethod), "24h")

    assert_equal 24, points.size
    assert_equal Time.current.utc.beginning_of_hour, points.last.first
    assert_equal 32, points.last.last
    assert_equal 1.hour, points[1].first - points[0].first
  end

  test "7d series has 28 six-hour buckets" do
    points = IssueHourlyCount.series(issues(:card_error), "7d")

    assert_equal 28, points.size
    assert_equal 6.hours, points[1].first - points[0].first
    assert_equal 0, points.last.first.to_i % 6.hours.to_i
    assert_equal IssueHourlyCount.where(issue: issues(:card_error), hour: points.first.first..).sum(:count), points.sum(&:last)
  end

  test "30d series has 30 day buckets in the given zone" do
    points = IssueHourlyCount.series(issues(:card_error), "30d")

    assert_equal 30, points.size
    assert_equal Time.current.utc.beginning_of_day, points.last.first
    assert_equal IssueHourlyCount.where(issue: issues(:card_error)).sum(:count), points.sum(&:last)
  end

  test "30d days are the viewer's local days" do
    pacific = ActiveSupport::TimeZone["America/Los_Angeles"]
    issue = issues(:card_error)
    IssueHourlyCount.where(issue:).delete_all
    travel_to Time.utc(2026, 10, 4, 20) do
      IssueHourlyCount.create!(issue:, hour: Time.utc(2026, 10, 3, 17), count: 1) # Oct 3 10:00 PDT

      points = IssueHourlyCount.series(issue, "30d", zone: pacific)
      day, count = points.find { |_, n| n.positive? }
      assert_equal [ Date.new(2026, 10, 3), 1 ], [ day.to_date, count ]
      assert_equal "America/Los_Angeles", day.time_zone.tzinfo.identifier
      assert_equal pacific.today, points.last.first.to_date
    end
  end

  test "unknown period falls back to 24h" do
    assert_equal 24, IssueHourlyCount.series(issues(:nomethod), "bogus").size
  end
end
