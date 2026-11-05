require "test_helper"

class Apm::StatsQueryTest < ActiveSupport::TestCase
  setup do
    @checkout = apm_transactions(:checkout_create)
    @products = apm_transactions(:products_show)
    @ids = [ @checkout.id, @products.id ]
  end

  def stats(key = "1d") = Apm::StatsQuery.new(Apm::Range.new(key))

  test "by_transaction sums the range's rows per transaction" do
    result = stats.by_transaction(@ids)
    hourly = ApmHourlyStat.where(apm_transaction_id: @checkout.id, hour: Apm::Range.new("1d").start..)
    assert_equal hourly.sum(:requests_count), result[@checkout.id].count
    assert_equal hourly.sum(:failed_count), result[@checkout.id].failed
    assert_equal result[@checkout.id].count, result[@checkout.id].counts.sum
    assert_in_delta hourly.sum(:duration_ms_sum), result[@checkout.id].duration_ms, 0.01
    assert_equal ApmFixtureStats::PRODUCTS[:count] * 60, stats("1h").by_transaction(@ids)[@products.id].count
  end

  test "the arrays come back in bucket order" do
    products = stats("15m").by_transaction([ @products.id ])[@products.id]
    assert_equal 15 * 8, products.counts[12]
    assert_equal 15 * 2, products.counts[14]
    assert_in_delta 15 * 260.0, products.view_ms[12]
  end

  test "last_hour and past_day read minute and hourly rows" do
    last_hour = stats.last_hour([ @checkout.id ])[@checkout.id]
    past_day = stats.past_day([ @checkout.id ])[@checkout.id]
    assert_equal 240, last_hour.count
    assert_operator past_day.count, :>, 23 * 240
    assert_operator last_hour.percentile(95), :>, 1_150
    assert_operator past_day.percentile(95), :<, 380
  end

  test "ids without data are absent and an empty id list costs nothing" do
    assert_equal({}, stats.by_transaction([ -1 ]))
    assert_no_queries { assert_equal({}, stats.by_transaction([])) }
  end

  test "series is zero-filled over the range's bins" do
    series = stats("1h").series(@products.id)
    assert_equal 60, series.size
    assert_equal Apm::Range.new("1h").bin_times, series.map(&:first)
    assert series.last(59).all? { |_, distribution| distribution.count == 10 }

    day = stats("1d").series(@products.id)
    assert_equal 96, day.size
    assert day.first(80).all? { |_, distribution| distribution.empty? }, "minute rows only cover the last 2 hours"
    assert_equal 150, day[-2].last.count
  end

  test "hourly_p95 gives one value per hour, nil without data" do
    values = stats.hourly_p95(@ids)
    assert_equal 24, values[@checkout.id].size
    assert values[@checkout.id].compact.size >= 23
    assert_operator values[@checkout.id].last, :>, values[@checkout.id].first
    assert_equal [ nil ] * 24, stats.hourly_p95([ -1 ])[-1]
  end

  test "each method is at most two statements, whatever the number of transactions" do
    query, ids = stats, ApmTransaction.ids
    assert_queries_count(2) { query.by_transaction(ids) }
    assert_queries_count(2) { query.series(@checkout.id) }
    assert_queries_count(1) { query.hourly_p95(ids) }
    assert_no_queries { query.by_transaction(ids.reverse) }
  end
end

class Apm::StatsQueryRankedTest < ActiveSupport::TestCase
  test "ranked sorts transactions with data by time consumed, p95, rate or failed" do
    ids = ApmTransaction.listed.where(project: projects(:storefront)).ids
    stats = Apm::StatsQuery.new(Apm::Range.new("1h"))
    checkout, products, job = %i[checkout_create products_show place_order_job].map { apm_transactions(it).id }

    assert_equal [ checkout, job, products ], stats.ranked(ids)
    assert_equal [ checkout, job, products ], stats.ranked(ids, sort: "p95")
    assert_equal [ products, checkout, job ], stats.ranked(ids, sort: "rate")
    assert_equal checkout, stats.ranked(ids, sort: "failed").first
    assert_equal stats.ranked(ids), stats.ranked(ids, sort: "bogus")
    assert_equal [], stats.ranked([ apm_transactions(:billing_invoices).id - 1_000_000 ])
  end
end
