require "test_helper"
require_relative "apm_test_support"

class Apm::EnvelopesTest < ActiveSupport::TestCase
  include ApmFixtureClock

  include ApmTestSupport

  def metrics_errors(transactions = nil, **body)
    data = JSON.parse(metrics_body(transactions || [ metrics_transaction ])).merge(body.deep_stringify_keys)
    Apm::MetricsEnvelope.new(data.to_json).errors
  end

  def tx_errors(**overrides) = metrics_errors([ metrics_transaction.merge(overrides) ])

  test "a well-formed metrics payload is valid and keeps its batch id" do
    envelope = Apm::MetricsEnvelope.new(metrics_body(batch_id: "0192F7B0-1A2B-7C3D-8E4F-5A6B7C8D9E0F"))
    assert envelope.valid?
    assert_equal "0192f7b0-1a2b-7c3d-8e4f-5a6b7c8d9e0f", envelope.batch_uuid
    assert Apm::TraceId.v7?(Apm::MetricsEnvelope.new(metrics_body(batch_id: "nope")).batch_uuid)
  end

  test "metrics body and minute shape" do
    assert_equal [ "body must be a JSON object" ], Apm::MetricsEnvelope.new("[]").errors
    assert_equal [ "histogram must be \"gs-v1\"" ], metrics_errors(histogram: "gs-v2")
    assert_equal [ "minutes must be an array of 1 to 5 entries" ], metrics_errors(minutes: [])
    assert_equal [ "minutes must be an array of 1 to 5 entries" ], metrics_errors(minutes: Array.new(6) { {} })
    assert_equal [ "minutes[0].minute must be the UTC start of a minute" ],
                 metrics_errors(minutes: [ { minute: "2026-11-04T14:32:10Z", transactions: [ metrics_transaction ] } ])
    assert_equal [ "minutes[0].transactions must be an array of 1 to 1000 entries" ],
                 metrics_errors(minutes: [ { minute: "2026-11-04T14:32:00Z", transactions: [] } ])
  end

  test "transaction fields" do
    assert_equal [ "minutes[0].transactions[0].kind must be \"web\" or \"job\"" ], tx_errors(kind: "cron")
    assert_equal [ "minutes[0].transactions[0].name must be a non-empty string" ], tx_errors(name: " ")
    assert_includes tx_errors(count: 0), "minutes[0].transactions[0].count must be an integer of at least 1"
    assert_equal [ "minutes[0].transactions[0].failed must be an integer from 0 to count" ], tx_errors(failed: 4)
    assert_equal [ "minutes[0].transactions[0].duration_ms must be a number >= 0" ], tx_errors(duration_ms: -1)
    assert_equal [ "minutes[0].transactions[0].route must be a string" ], tx_errors(route: 5)
  end

  test "buckets" do
    prefix = "minutes[0].transactions[0]."
    assert_equal [ "#{prefix}buckets must add up to count" ], tx_errors(count: 4)
    assert_equal [ "#{prefix}buckets must not repeat an index" ], tx_errors(buckets: [ [ 15, 2, 0, 0, 0, 0 ], [ 15, 1, 0, 0, 0, 0 ] ])
    [ [ [ 31, 3, 0, 0, 0, 0 ] ], [ [ 15, 3, -1, 0, 0, 0 ] ], [ [ 15, 3, 0, 0, 0 ] ], [ [ 15, 0, 0, 0, 0, 0 ] ], [ "x" ] ].each do |buckets|
      assert_equal [ "#{prefix}buckets entries must be [index, count, db_ms, http_ms, view_ms, ruby_ms]" ], tx_errors(buckets:), buckets.inspect
    end
    assert_equal [ "#{prefix}buckets must be an array of 1 to 31 entries" ], tx_errors(buckets: [])
  end

  test "queue wait" do
    prefix = "minutes[0].transactions[0]."
    assert_empty tx_errors(queue_wait: [ [ 11, 3 ] ], queue_wait_ms: 5)
    assert_equal [ "#{prefix}queue_wait must add up to at most count" ], tx_errors(queue_wait: [ [ 11, 4 ] ])
    assert_equal [ "#{prefix}queue_wait entries must be [index, count]" ], tx_errors(queue_wait: [ [ 40, 1 ] ])
    assert_equal [ "#{prefix}queue_wait_ms must be a number >= 0" ], tx_errors(queue_wait_ms: "5")
  end

  test "errors are capped and never echo values" do
    errors = metrics_errors(Array.new(50) { metrics_transaction(name: "mara@example.com", kind: "nope") })
    assert_equal Apm::ShapeErrors::MAX, errors.size
    assert errors.none? { it.include?("mara") }
  end

  test "malformed JSON raises InvalidJson" do
    assert_raises(Ingest::InvalidJson) { Apm::MetricsEnvelope.new("{nope") }
    assert_raises(Ingest::InvalidJson) { Apm::TracesEnvelope.new("") }
  end

  test "traces payload shape" do
    assert Apm::TracesEnvelope.new(traces_body).valid?
    assert_equal [ "traces must be an array of 1 to 50 entries" ], Apm::TracesEnvelope.new(traces_body([])).errors
    assert_equal [ "traces must be an array of 1 to 50 entries" ], Apm::TracesEnvelope.new(traces_body(Array.new(51) { trace_hash })).errors
    bad = trace_hash.merge(kind: "x", minute: "2026-11-04T14:32:01Z", started_at: "yesterday", duration_ms: "1", db_ms: -1,
                     host: 1, status: "200", spans: {})
    assert_equal [ "traces[0].kind must be \"web\" or \"job\"", "traces[0].minute must be the UTC start of a minute",
                   "traces[0].started_at must be an ISO 8601 timestamp", "traces[0].duration_ms must be a number >= 0",
                   "traces[0].db_ms must be a number >= 0", "traces[0].host must be a string", "traces[0].status must be an integer",
                   "traces[0].spans must be an array" ], Apm::TracesEnvelope.new(traces_body([ bad ])).errors
  end
end
