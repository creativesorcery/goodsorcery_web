require "test_helper"

class TimeHelperTest < ActionView::TestCase
  include TimeHelper

  setup { travel_to Time.utc(2026, 10, 4, 12, 0, 0) }

  test "time_ago_compact uses short units" do
    assert_equal "just now", time_ago_compact(20.seconds.ago)
    assert_equal "just now", time_ago_compact(1.minute.from_now)
    assert_equal "2 min ago", time_ago_compact(2.minutes.ago)
    assert_equal "3h ago", time_ago_compact(3.hours.ago)
    assert_equal "12d ago", time_ago_compact(12.days.ago)
    assert_equal "9mo ago", time_ago_compact(275.days.ago)
    assert_equal "1y ago", time_ago_compact(400.days.ago)
    assert_equal "never", time_ago_compact(nil)
  end

  test "first_seen_label" do
    assert_equal "first 3h ago", first_seen_label(3.hours.ago)
  end

  test "clock_label shows today, a date, or a dated year in the user's zone" do
    Time.use_zone("Europe/London") do
      assert_equal "Today 10:14", clock_label(Time.utc(2026, 10, 4, 9, 14))
      assert_equal "Oct 3 09:14", clock_label(Time.utc(2026, 10, 3, 8, 14))
      assert_equal "Dec 31 2025 23:00", clock_label(Time.utc(2025, 12, 31, 23, 0))
    end
    assert_equal "—", clock_label(nil)
  end
end
