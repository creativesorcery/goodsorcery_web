require "test_helper"

class Apm::RangeTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 4, 14, 32, 40)

  def entitlements(days, hosted: true)
    Entitlements.new({ "apm_retention_days" => days }, hosted:, hosted_defaults: {}, self_hosted_apm_retention_days: 30)
  end

  test "starts, bins and rows per key" do
    { "15m" => [ Time.utc(2026, 11, 4, 14, 18), :minute, 15, 1.minute ],
      "1h" => [ Time.utc(2026, 11, 4, 13, 33), :minute, 60, 1.minute ],
      "1d" => [ Time.utc(2026, 11, 3, 15), :hour, 96, 15.minutes ],
      "7d" => [ Time.utc(2026, 10, 28, 15), :hour, 84, 2.hours ],
      "30d" => [ Time.utc(2026, 10, 5, 15), :hour, 90, 8.hours ] }.each do |key, (start, rows, bins, bin)|
      range = Apm::Range.new(key, now: NOW)
      assert_equal start, range.start, key
      assert_equal [ rows, bins, bin ], [ range.figure_rows, range.bins, range.bin ], key
      assert_equal bins, range.bin_times.size
      assert_operator range.bin_times.last, :<=, NOW
      assert_operator range.bin_times.last + bin, :>, NOW
    end
    assert_equal :minute, Apm::Range.new("1d").chart_rows
    assert_equal "last 24 hours", Apm::Range.new("1d").label
  end

  test "the start is clamped to the retention" do
    range = Apm::Range.new("30d", now: NOW, retention_days: 7)
    assert_equal NOW - 7.days, range.start
  end

  test "pick falls back to 1d for unknown and locked keys" do
    assert_equal "1d", Apm::Range.pick("nope", entitlements: entitlements(30)).key
    assert_equal "1d", Apm::Range.pick("7d", entitlements: entitlements(1)).key
    assert_equal "7d", Apm::Range.pick("7d", entitlements: entitlements(7)).key
    assert_equal "15m", Apm::Range.pick("15m", entitlements: entitlements(1)).key
    assert Apm::Range.new("30d").locked?(entitlements(7))
    assert_not Apm::Range.new("1d").locked?(entitlements(1))
  end

  test "minutes elapsed and cache key" do
    range = Apm::Range.new("15m", now: NOW)
    assert_in_delta 14 + 40 / 60.0, range.minutes
    assert_equal [ "15m", Time.utc(2026, 11, 4, 14, 32).to_i ], range.cache_key
  end
end
