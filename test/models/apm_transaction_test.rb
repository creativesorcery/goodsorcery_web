require "test_helper"

class ApmTransactionTest < ActiveSupport::TestCase
  test "scopes: listed, totals, kinds, environment" do
    storefront = projects(:storefront).apm_transactions
    assert_equal %w[CheckoutsController#create Orders::PlaceJob ProductsController#show], storefront.listed.pluck(:name).sort
    assert_equal [ "All background jobs", "All web requests" ], storefront.totals.pluck(:name).sort
    assert_equal 2, storefront.listed.web.count
    assert_equal [ "Orders::PlaceJob" ], storefront.listed.jobs.pluck(:name)
    assert_empty storefront.for_environment("staging")
  end

  test "matching filters name and route case-insensitively and escapes LIKE wildcards" do
    scope = projects(:storefront).apm_transactions.listed
    assert_equal [ "CheckoutsController#create" ], scope.matching("checkout").pluck(:name)
    assert_equal [ "ProductsController#show" ], scope.matching("/products/:").pluck(:name)
    assert_empty scope.matching("%")
    assert_equal 3, scope.matching("  ").count
  end

  test "labels" do
    checkout = apm_transactions(:checkout_create)
    assert_equal "POST /checkout", checkout.route_label
    assert checkout.web?
    assert_nil apm_transactions(:place_order_job).route_label
    assert apm_transactions(:place_order_job).job?
  end

  test "total_for and environments_of" do
    assert_equal apm_transactions(:storefront_web_total), ApmTransaction.total_for(projects(:storefront), "production", "web")
    assert_nil ApmTransaction.total_for(projects(:storefront), "staging", "web")
    assert_equal [ "production" ], ApmTransaction.environments_of(projects(:storefront))
  end

  test "requests by environment reads the total rows" do
    counts = ApmHourlyStat.requests_by_environment(projects(:storefront), since: 2.hours.ago)
    assert_operator counts["production"], :>, 0
  end

  test "deleting a project cascades to its performance data" do
    project, transaction_id = projects(:umbrella_app), apm_transactions(:umbrella_home).id
    project.delete
    assert_not ApmTransaction.exists?(project_id: project.id)
    assert_not ApmTrace.exists?(project_id: project.id)
    assert_not ApmMinuteStat.exists?(apm_transaction_id: transaction_id)
  end
end
