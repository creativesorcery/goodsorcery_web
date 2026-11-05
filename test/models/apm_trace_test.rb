require "test_helper"
require_relative "ingest/ingest_test_support"

class ApmTraceTest < ActiveSupport::TestCase
  include IngestTestSupport

  test "the payload is ciphertext at rest and decrypts into details" do
    trace = apm_traces(:checkout_slow)
    raw = raw_column(ApmTrace, :payload, trace.id)
    %w[apm-fixture-secret products taxjar checkout].each { |text| assert_not_includes raw, text }

    details = trace.details
    assert_equal "/checkout", details.request["path"]
    assert_equal "web-2", details.host
    group = details.n_plus_one_spans.sole
    assert_equal 38, group.calls
    assert group.n_plus_one?
    assert_equal :db, group.layer
    assert_in_delta 1215.2, group.extent_ms
    assert_equal "app/services/cart_total.rb:27", group.call_site.location
    assert_equal "total_cents", group.call_site.method_name
    assert_equal 5, group.call_site.lines.size
    assert_equal %w[sql sql http view enqueue], details.spans.map(&:type)
    assert_equal "POST", details.spans[2].http_method
  end

  test "sorting, range and N+1 scopes" do
    traces = projects(:storefront).apm_traces
    assert_equal apm_traces(:checkout_slow), traces.sorted("slowest").first
    assert_equal apm_traces(:checkout_failed), traces.sorted("newest").first
    assert_equal traces.slowest_first.to_a, traces.sorted("bogus").to_a
    assert_not_includes traces.since(2.hours.ago), apm_traces(:checkout_old_hour)
    ids = ApmTrace.transaction_ids_with_n_plus_one(ApmTransaction.ids, since: 1.day.ago)
    assert_equal Set[apm_transactions(:checkout_create).id], ids
  end

  test "listing: a transaction's traces in a range, sorted and paged by 20" do
    checkout = apm_transactions(:checkout_create)
    assert_equal [ apm_traces(:checkout_slow), apm_traces(:checkout_failed), apm_traces(:checkout_old_hour) ],
                 ApmTrace.listing(checkout, Apm::Range.new("1d")).to_a
    assert_equal [ apm_traces(:checkout_failed), apm_traces(:checkout_slow) ], ApmTrace.listing(checkout, Apm::Range.new("1h"), sort: "newest").to_a
    assert_equal 3, ApmTrace.listing(checkout, Apm::Range.new("1d")).count

    minute = TimeSeries.align(30.minutes.ago, 1.minute)
    ApmTrace.insert_all(Array.new(25) do |index|
      at = minute - index.minutes - 10.minutes
      { project_id: checkout.project_id, apm_transaction_id: checkout.id, uuid: Apm::TraceId.generate(at), minute: at,
        hour: TimeSeries.align(at, 1.hour), started_at: at, duration_ms: 1, payload: "{}", created_at: at }
    end)
    listing = ApmTrace.listing(checkout, Apm::Range.new("1d"))
    assert_equal 20, listing.page_of(1).to_a.size
    assert_equal 8, listing.page_of(2).to_a.size
    assert_equal listing.page_of(1).to_a, listing.page_of(-3).to_a
  end

  test "short id, older and newer" do
    slow, failed, old = apm_traces(:checkout_slow), apm_traces(:checkout_failed), apm_traces(:checkout_old_hour)
    assert_equal slow.uuid.delete("-").last(8), slow.short_id
    assert_equal slow.uuid, slow.to_param
    assert_equal old, slow.older(since: 1.day.ago)
    assert_nil slow.older(since: 1.hour.ago), "past the cutoff"
    assert_equal failed, slow.newer(since: 1.day.ago)
    assert_nil failed.newer(since: 1.day.ago)
  end

  test "error_occurrence resolves the reported event in the same project" do
    assert_equal occurrences(:nomethod_latest), apm_traces(:checkout_failed).error_occurrence
    assert_nil apm_traces(:checkout_slow).error_occurrence
  end

  test "open_hour?" do
    assert_not apm_traces(:checkout_old_hour).open_hour?
    assert apm_traces(:checkout_failed).open_hour?(now: apm_traces(:checkout_failed).minute)
  end
end
