require "test_helper"

class Apm::HistogramTest < ActiveSupport::TestCase
  include ApmFixtureClock

  test "the gs-v1 bounds, element by element (shared with the gem; never change without a new scheme)" do
    expected = [ 1, 1.5, 2, 3, 4.5, 6.5, 9.5, 14, 20, 28,
                 40, 60, 85, 125, 180, 260, 380, 550, 800, 1_150,
                 1_700, 2_450, 3_550, 5_100, 7_500, 11_000, 16_000, 23_000, 33_000, 48_000 ]
    assert_equal 30, Apm::Histogram::BOUNDS_MS.size
    expected.each_with_index { |bound, index| assert_equal bound, Apm::Histogram::BOUNDS_MS[index], "bound #{index}" }
    assert_equal 31, Apm::Histogram::BUCKETS
    assert_equal "gs-v1", Apm::Histogram::SCHEME
  end

  test "index is the number of bounds <= ms" do
    { 0 => 0, 0.4 => 0, 0.999 => 0, 1 => 1, 1.2 => 1, 250 => 15, 47_999 => 29, 48_000 => 30, 60_000 => 30, 1_000_000 => 30 }
      .each { |ms, index| assert_equal index, Apm::Histogram.index(ms), "#{ms} ms" }
  end
end
