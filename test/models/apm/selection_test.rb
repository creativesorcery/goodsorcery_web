require "test_helper"
require_relative "../../test_helpers/performance_pages_test_helper"

class Apm::SelectionTest < ActiveSupport::TestCase
  include PerformancePagesTestHelper

  setup { @project = projects(:storefront) }

  test "the trace page is capped so a huge number can't overflow the offset" do
    assert_equal ApmTrace::MAX_PAGE, select_with(page: "99999999999999999999").page
  end

  test "defaults: the app's default environment, 1d, time sort, slowest traces, page 1" do
    selection = select_with({})

    assert_equal "production", selection.environment
    assert_equal "1d", selection.range.key
    assert_nil selection.requested_tab
    assert_equal "time", selection.sort
    assert_equal "", selection.query
    assert_not selection.all?
    assert_equal "slowest", selection.trace_sort
    assert_equal 1, selection.page
    assert_equal({ env: "production", range: "1d" }, selection.link_params)
  end

  test "known values are read and unknown ones fall back" do
    selection = select_with(range: "7d", tab: "jobs", sort: "p95", q: "  Checkout ", all: "1", traces: "newest", page: "3")
    assert_equal [ "7d", "jobs", "p95", "Checkout", true, "newest", 3 ],
      [ selection.range.key, selection.requested_tab, selection.sort, selection.query, selection.all?, selection.trace_sort, selection.page ]

    odd = select_with(range: "2y", tab: "all", sort: "name", traces: "random", page: "-4", env: [ "production" ])
    assert_equal [ "1d", nil, "time", "slowest", 1, "production" ],
      [ odd.range.key, odd.requested_tab, odd.sort, odd.trace_sort, odd.page, odd.environment ]
  end

  test "the filter is capped at 100 characters" do
    assert_equal 100, select_with(q: "x" * 300).query.size
  end

  test "an environment without data falls back; the busiest wins without a usable default" do
    create_apm_transaction(@project, "HomeController#index", environment: "staging")
    assert_equal "staging", select_with(env: "staging").environment
    assert_equal "production", select_with(env: "qa").environment

    @project.update_column(:default_environment, nil)
    ApmHourlyStat.where(apm_transaction: [ apm_transactions(:storefront_web_total), apm_transactions(:storefront_jobs_total) ]).delete_all
    staging_total = @project.apm_transactions.create!(environment: "staging", kind: "web", name: "All web requests", total: true,
                                                      first_seen_at: 1.hour.ago, last_seen_at: 1.hour.ago)
    add_apm_stats(staging_total, count: 50)
    assert_equal "staging", select_with({}).environment
  end

  test "no environment for an app without data" do
    assert_nil Apm::Selection.new(projects(:marketing), {}, entitlements: accounts(:acme).entitlements).environment
  end

  test "a fixed environment ignores the param" do
    selection = Apm::Selection.new(@project, { env: "staging" }, entitlements: accounts(:acme).entitlements, environment: "production")
    assert_equal "production", selection.environment
  end

  test "a locked range falls back to 1d when hosted" do
    with_hosted_mode { assert_equal "1d", select_with(range: "30d").range.key }
  end

  private
    def select_with(params)
      Apm::Selection.new(@project, ActionController::Parameters.new(params), entitlements: accounts(:acme).entitlements)
    end
end
