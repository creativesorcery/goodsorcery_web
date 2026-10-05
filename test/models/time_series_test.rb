require "test_helper"

class TimeSeriesTest < ActiveSupport::TestCase
  setup { @from = Time.utc(2026, 10, 4, 0) }

  test "zero-fills missing buckets" do
    series = TimeSeries.new({ @from + 2.hours => 5 }, from: @from, step: 1.hour, buckets: 4)
    assert_equal [ 0, 0, 5, 0 ], series.values
  end

  test "sums counts that fall into the same bucket and ignores out-of-range times" do
    counts = { @from + 1.hour => 2, @from + 5.hours => 3, @from - 1.hour => 99, @from + 13.hours => 99 }
    series = TimeSeries.new(counts, from: @from, step: 6.hours, buckets: 2)
    assert_equal [ 5, 0 ], series.values
  end

  test "points pair bucket starts with counts" do
    points = TimeSeries.new({}, from: @from + 10.minutes, step: 1.hour, buckets: 2).points
    assert_equal [ [ @from, 0 ], [ @from + 1.hour, 0 ] ], points
  end

  test "window start makes the last bucket contain now" do
    now = Time.utc(2026, 10, 4, 9, 14)
    assert_equal Time.utc(2026, 10, 3, 10), TimeSeries.window_start(1.hour, 24, now:)
    assert_equal Time.utc(2026, 9, 5), TimeSeries.window_start(1.day, 30, now:)
  end

  test "align uses UTC epoch boundaries" do
    assert_equal Time.utc(2026, 10, 4, 6), TimeSeries.align(Time.utc(2026, 10, 4, 9, 14), 6.hours)
  end
end
