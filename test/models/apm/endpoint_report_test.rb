require "test_helper"
require_relative "../../test_helpers/performance_pages_test_helper"

class Apm::EndpointReportTest < ActiveSupport::TestCase
  include PerformancePagesTestHelper

  setup { @checkout = apm_transactions(:checkout_create) }

  test "the ribbon is Requests, Average, p75, p90, p95, p99 and Failed; only p95 carries the Slower ratio" do
    ribbon = report.ribbon

    assert_equal %i[requests average p75 p90 p95 p99 failed], ribbon.map(&:key)
    assert ribbon.all? { it.value && it.last_hour }
    assert_operator ribbon.find { it.key == :p95 }.change, :>=, Apm::SLOWER_RATIO
    assert ribbon.reject { it.key == :p95 }.all? { it.change.nil? }
  end

  test "five lines over the range's bins and five bars that sum to their values" do
    series = report.series
    assert_equal [ :average, 75, 90, 95, 99 ], series.lines.keys
    assert series.lines.values.all? { it.size == 96 }

    bars = report.bars
    assert_equal [ :average, 75, 90, 95, 99 ], bars.map(&:key)
    bars.each { |bar| assert_in_delta bar.value, bar.split.values.sum, 0.001 }
    assert_match(/\AAround p95 and p99, .+\.\z/, report.summary_sentence)
  end

  test "issues: unresolved, this transaction and environment only" do
    assert_equal [ issues(:nomethod) ], report.issues
    assert_equal 1, report.issues_count

    issues(:nomethod).update_columns(status: "resolved")
    assert_empty report.issues
  end

  test "climbing since is the start of the run of high hours" do
    since = report.climbing_since
    assert since.nil? || since <= Time.current
  end

  test "a transaction without data in the range" do
    quiet = @checkout.project.apm_transactions.create!(environment: "production", kind: "web", name: "QuietController#show",
                                                        first_seen_at: 1.day.ago, last_seen_at: 1.day.ago)
    quiet_report = report(quiet)

    assert quiet_report.empty?
    assert_empty quiet_report.bars
    assert_nil quiet_report.summary_sentence
    assert_nil quiet_report.slower_ratio
  end

  private
    def report(transaction = @checkout)
      selection = Apm::Selection.new(transaction.project, {}, entitlements: accounts(:acme).entitlements, environment: transaction.environment)
      Apm::EndpointReport.new(transaction, selection)
    end
end
