require "test_helper"
require_relative "../../test_helpers/performance_pages_test_helper"

class Apm::OverviewTest < ActiveSupport::TestCase
  include PerformancePagesTestHelper

  setup { @project = projects(:storefront) }

  test "tiles: Requests per minute, Average, p75, p90, p95, p99 and Failed with last-hour values" do
    tiles = overview.tiles

    assert_equal %i[rate average p75 p90 p95 p99 failed], tiles.map(&:key)
    assert tiles.all? { it.value && it.last_hour }
    assert_equal [ :rate, :duration, :duration, :duration, :duration, :duration, :percent ], tiles.map(&:format)
    p95 = tiles.find { it.key == :p95 }
    assert_operator p95.change, :>, 50
    assert tiles.reject { it.key == :p95 }.all? { it.change.nil? }
  end

  test "the jobs tab reads the job total and is not Slower" do
    tiles = overview(tab: "jobs").tiles

    assert_equal "Runs per minute", tiles.first.label
    assert_nil tiles.find { it.key == :p95 }.change
  end

  test "rows by time consumed with shares, Slower and N+1" do
    rows = overview.rows

    assert_equal %w[CheckoutsController#create ProductsController#show], rows.map { it.transaction.name }
    checkout = rows.first
    assert checkout.slower?
    assert checkout.n_plus_one
    assert_equal 24, checkout.sparkline.size
    assert_in_delta 1.0, rows.sum(&:share), 0.001
    assert_not rows.last.slower?
  end

  test "tab counts and a default tab of jobs when only jobs sent data" do
    assert_equal({ "web" => 2, "jobs" => 1 }, overview.tab_counts)

    ApmTransaction.where(project: @project, kind: "web").delete_all
    assert_equal "jobs", overview.tab
  end

  test "the chart has the range's bins with a layer split and p95 where there is data" do
    chart = overview.chart

    assert_equal 96, chart.size
    last = chart.last
    assert_in_delta last.average_ms, last.split.values.sum, 0.001
    assert last.p95
  end

  test "link params keep the tab, a non-default sort and the filter" do
    assert_equal({ env: "production", range: "1d", tab: "web", sort: "p95", q: "check" }, overview(sort: "p95", q: "check").link_params)
    assert_equal({ env: "production", range: "1h", tab: "jobs" }, overview(tab: "jobs").link_params(range: "1h"))
  end

  private
    def overview(**params)
      selection = Apm::Selection.new(@project, ActionController::Parameters.new(params), entitlements: accounts(:acme).entitlements)
      Apm::Overview.new(@project, selection)
    end
end
