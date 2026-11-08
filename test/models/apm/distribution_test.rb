require "test_helper"

class Apm::DistributionTest < ActiveSupport::TestCase
  include ApmFixtureClock

  def dist(buckets, count: buckets.sum { it[1] }, duration_ms: 0.0, **options)
    Apm::Distribution.from_buckets(count:, failed: 0, duration_ms:, buckets:, **options)
  end

  test "an empty distribution has no average, percentile or split" do
    empty = Apm::Distribution.empty
    assert empty.empty?
    assert_nil empty.average_ms
    assert_nil empty.percentile(95)
    assert_nil empty.layer_split(95)
    assert_nil empty.layer_split(:average)
    assert_nil empty.failed_rate
    assert_nil empty.queue_wait_percentile(95)
  end

  test "average is sum over count" do
    assert_in_delta 250.0, dist([ [ 15, 4, 0, 0, 0, 1000 ] ], duration_ms: 1000.0).average_ms
  end

  test "a single bucket interpolates geometrically between its bounds" do
    one = dist([ [ 15, 1, 0, 0, 0, 200 ] ])
    # rank 1, f = 0.5: the geometric centre of 180..260.
    assert_in_delta Math.sqrt(180 * 260), one.percentile(50), 0.001
    assert_in_delta Math.sqrt(180 * 260), one.percentile(99), 0.001

    hundred = dist([ [ 15, 100, 0, 0, 0, 20_000 ] ])
    assert_in_delta 180 * ((260.0 / 180)**(94.5 / 100)), hundred.percentile(95), 0.001
    assert_operator hundred.percentile(50), :<, hundred.percentile(95)
  end

  test "bucket 0 is linear between 0 and 1 ms" do
    assert_in_delta 0.5, dist([ [ 0, 1, 0, 0, 0, 0.5 ] ]).percentile(50), 0.0001
  end

  test "percentiles across a spread pick the bucket where the rank falls" do
    spread = dist([ [ 10, 90, 0, 0, 0, 0 ], [ 20, 10, 0, 0, 0, 0 ] ])
    assert_equal 10, spread.percentile_bucket(90)
    assert_equal 20, spread.percentile_bucket(95)
    assert spread.percentile(90).between?(28, 40)
    assert spread.percentile(95).between?(1_150, 1_700)
    assert spread.percentile(99).between?(spread.percentile(95), 1_700)
  end

  test "rank uses exact arithmetic (95% of 100 is rank 95, not 96)" do
    spread = dist([ [ 10, 95, 0, 0, 0, 0 ], [ 20, 5, 0, 0, 0, 0 ] ])
    assert_equal 10, spread.percentile_bucket(95)
  end

  test "the overflow bucket reports its own mean, at least 48 s" do
    assert_in_delta 60_000.0, dist([ [ 30, 2, 0, 0, 0, 120_000 ] ]).percentile(99)
    assert_in_delta 48_000.0, dist([ [ 30, 2, 0, 0, 0, 10 ] ]).percentile(99)
  end

  test "layer split of a percentile uses its bucket's proportions and sums to the value" do
    spread = dist([ [ 15, 90, 9000, 0, 9000, 0 ], [ 20, 10, 6000, 4000, 0, 2000 ] ], duration_ms: 30_000.0)
    split = spread.layer_split(95)
    assert_in_delta spread.percentile(95), split.values.sum, 0.0001
    assert_in_delta 0.5, split[:db] / split.values.sum, 0.0001
    assert_in_delta 0.0, split[:view]

    average = spread.layer_split(:average)
    assert_in_delta 300.0, average.values.sum, 0.0001
    assert_in_delta 15_000.0 / 30_000 * 300, average[:db], 0.0001
  end

  test "a bucket without layer time puts everything in ruby" do
    split = dist([ [ 15, 1, 0, 0, 0, 0 ] ]).layer_split(50)
    assert_equal 0.0, split[:db]
    assert_operator split[:ruby], :>, 0
  end

  test "+ adds element-wise and round-trips through to_h" do
    a = dist([ [ 3, 2, 1, 1, 1, 1 ] ], duration_ms: 5.0, queue_wait: [ [ 11, 2 ] ], queue_wait_ms: 90.0)
    b = dist([ [ 3, 1, 1, 0, 0, 0 ], [ 9, 1, 0, 0, 0, 25 ] ], duration_ms: 30.0)
    sum = a + b
    assert_equal 4, sum.count
    assert_equal 3, sum.counts[3]
    assert_equal 2.0, sum.db_ms[3]
    assert_equal 35.0, sum.duration_ms
    assert_equal 2, sum.queue_wait_count
    assert_in_delta 45.0, sum.queue_wait_average_ms
    assert sum.queue_wait_percentile(95).between?(40, 60)
    assert_equal sum.to_h, Apm::Distribution.from_h(sum.to_h.as_json).to_h
  end

  test "failed rate and rate per minute" do
    d = Apm::Distribution.from_buckets(count: 50, failed: 1, duration_ms: 0, buckets: [ [ 5, 50, 0, 0, 0, 0 ] ])
    assert_in_delta 0.02, d.failed_rate
    assert_in_delta 5.0, d.rate_per_minute(10)
  end
end
