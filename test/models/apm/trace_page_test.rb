require "test_helper"

class Apm::TracePageTest < ActiveSupport::TestCase
  include ApmFixtureClock

  test "title, request id, layers and the N+1 group" do
    page = page_for(:checkout_slow)

    assert_equal "POST /checkout", page.title
    assert_equal "7f3a9c1e", page.request_id
    assert page.open_hour?
    assert_equal %i[db http view ruby], page.layers.map(&:first)
    assert_in_delta 1.0, page.layers.sum(&:last), 0.001
    assert_equal 38, page.n_plus_one.calls
  end

  test "axis ticks are round steps ending at the duration" do
    ticks = page_for(:checkout_slow).axis_ticks

    assert_equal [ 0, 500, 1000, 1500, 2000, 2500 ], ticks[0...-1].map(&:first)
    assert_equal [ 2940.2, 1.0 ], ticks.last
  end

  test "errors, older and newer" do
    failed = page_for(:checkout_failed)
    assert failed.error_reported?
    assert_equal issues(:nomethod), failed.error_issue
    assert_nil failed.newer
    assert_equal apm_traces(:checkout_slow), failed.older

    assert_nil page_for(:checkout_slow).error_issue
    assert_not page_for(:checkout_old_hour).open_hour?
  end

  test "a job's title is its class" do
    trace = apm_traces(:checkout_slow)
    trace.apm_transaction = apm_transactions(:place_order_job)
    assert_equal "Orders::PlaceJob", Apm::TracePage.new(trace, cutoff: 30.days.ago).title
  end

  private
    def page_for(name) = Apm::TracePage.new(apm_traces(name), cutoff: 30.days.ago)
end
