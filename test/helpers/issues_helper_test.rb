require "test_helper"

class IssuesHelperTest < ActionView::TestCase
  include ::NumberHelper

  test "hourly histogram titles keep the minutes of half-hour zones" do
    travel_to Time.utc(2026, 10, 4, 9, 10) do
      Time.use_zone("Asia/Kolkata") do
        assert_equal [ "13:30 · 1 event", "14:30 · 2 events" ], send(:hourly_titles, [ 1, 2 ])
      end
    end
  end
end
