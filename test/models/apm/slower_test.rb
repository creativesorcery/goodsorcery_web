require "test_helper"

class Apm::SlowerTest < ActiveSupport::TestCase
  include ApmFixtureClock

  def dist(count, bucket) = Apm::Distribution.from_buckets(count:, failed: 0, duration_ms: 0, buckets: [ [ bucket, count, 0, 0, 0, 0 ] ])

  test "the fixture checkout is Slower and the steady endpoint is not" do
    ratios = Apm::Slower.new(Apm::StatsQuery.new(Apm::Range.new)).ratios(ApmTransaction.ids)
    assert_operator ratios[apm_transactions(:checkout_create).id], :>=, Apm::SLOWER_RATIO
    assert_not ratios.key?(apm_transactions(:products_show).id)
    assert_not ratios.key?(apm_transactions(:place_order_job).id)
  end

  test "thresholds: the ratio and both minimum counts" do
    assert Apm::Slower.ratio(dist(30, 20), dist(100, 15))
    assert_nil Apm::Slower.ratio(dist(29, 20), dist(100, 15)), "too few in the last hour"
    assert_nil Apm::Slower.ratio(dist(30, 20), dist(99, 15)), "too few in the day"
    assert_nil Apm::Slower.ratio(dist(30, 16), dist(100, 15)), "under 1.5x"
    assert_nil Apm::Slower.ratio(Apm::Distribution.empty, dist(100, 15))
  end
end
