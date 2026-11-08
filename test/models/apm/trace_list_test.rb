require "test_helper"
require_relative "../../test_helpers/performance_pages_test_helper"

class Apm::TraceListTest < ActiveSupport::TestCase
  include ApmFixtureClock

  include PerformancePagesTestHelper

  setup do
    @checkout = apm_transactions(:checkout_create)
    @range = Apm::Range.new("1d")
  end

  test "slowest first, newest first, and the issue of a reported error" do
    slowest = Apm::TraceList.new(@checkout, @range, sort: "slowest", page: 1)
    assert_equal %i[checkout_slow checkout_failed checkout_old_hour].map { apm_traces(it) }, slowest.traces
    assert_equal 3, slowest.total
    assert_equal issues(:nomethod), slowest.issue_for(apm_traces(:checkout_failed))
    assert_nil slowest.issue_for(apm_traces(:checkout_slow))

    newest = Apm::TraceList.new(@checkout, @range, sort: "newest", page: 1)
    assert_equal apm_traces(:checkout_failed), newest.traces.first
  end

  test "linked issues come with their project loaded, without querying projects" do
    list = Apm::TraceList.new(@checkout, @range, sort: "slowest", page: 1)
    failed = apm_traces(:checkout_failed)
    list.traces
    @checkout.project
    assert_no_queries_match(/FROM "projects"/) do
      issue = list.issue_for(failed)
      assert issue.association(:project).loaded?
      issue.short_id
    end
  end

  test "pages of 20" do
    transaction = create_apm_transaction(projects(:storefront), "ReportsController#index")
    45.times { |i| create_apm_trace(transaction, minutes_ago: i + 1) }

    second = Apm::TraceList.new(transaction, @range, sort: "newest", page: 2)
    assert_equal 20, second.traces.size
    assert_equal [ 21, 40 ], [ second.first_number, second.last_number ]
    assert second.previous_page?
    assert second.next_page?
    assert_not Apm::TraceList.new(transaction, @range, sort: "newest", page: 3).next_page?
  end

  test "the range bounds the list" do
    list = Apm::TraceList.new(@checkout, Apm::Range.new("1h"), sort: "slowest", page: 1)
    assert_not_includes list.traces, apm_traces(:checkout_old_hour)
  end
end
