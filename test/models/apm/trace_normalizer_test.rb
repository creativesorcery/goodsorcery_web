require "test_helper"
require_relative "apm_test_support"

class Apm::TraceNormalizerTest < ActiveSupport::TestCase
  include ApmFixtureClock

  include ApmTestSupport

  def normalize(trace = trace_hash) = Apm::TraceNormalizer.new.normalize(trace.deep_stringify_keys)

  test "columns: ids, layers, counts and outcome" do
    trace = trace_hash(error_event_id: "0192F7A4-6C1E-7B3A-9D21-5F0C8E1B0AA1")
    result = normalize(trace)
    columns = result.columns
    assert_equal trace[:id], columns[:uuid]
    assert_equal [ 2940.2, 1220.4, 1230.0, 320.1, 169.7 ], columns.values_at(:duration_ms, :db_ms, :http_ms, :view_ms, :ruby_ms)
    assert_equal [ 43, 2, 1 ], columns.values_at(:sql_count, :http_count, :n_plus_one_count)
    assert_equal [ 200, false ], columns.values_at(:status, :failed)
    assert_equal "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1", columns[:error_event_uuid]
    assert_equal TimeSeries.align(columns[:minute], 1.hour), columns[:hour]
    assert_equal [ "web", "CheckoutsController#create", "POST", "/checkout" ],
                 [ result.kind, result.name, result.labels[:http_method], result.labels[:route] ]
  end

  test "app_ms fills the app-code column; the older ruby_ms key still does" do
    old_form = normalize(trace_hash).columns
    new_form = normalize(trace_hash(ruby_ms: nil, app_ms: 42.5)).columns
    both = normalize(trace_hash(app_ms: 12.0)).columns
    neither = normalize(trace_hash(ruby_ms: nil)).columns

    assert_equal [ 169.7, 42.5, 12.0, 0.0 ], [ old_form, new_form, both, neither ].map { it[:ruby_ms] }
  end

  test "the runtime is stored as a list, from the list or the older object" do
    rust = [ { name: "Rust", version: "1.82.0" }, { name: "axum", version: "0.8.1" }, { name: "bad name!", version: "1" } ]
    listed = JSON.parse(normalize(trace_hash(runtime: rust)).payload)["runtime"]
    legacy = JSON.parse(normalize.payload)["runtime"]

    assert_equal [ { "name" => "Rust", "version" => "1.82.0" }, { "name" => "axum", "version" => "0.8.1" } ], listed
    assert_equal [ { "name" => "Rails", "version" => "8.0.2" }, { "name" => "Ruby", "version" => "3.4.1" } ], legacy
    assert_equal [], JSON.parse(normalize(trace_hash(runtime: "Rust")).payload)["runtime"]
  end

  test "the payload allow-lists keys and strips query strings, userinfo and literals" do
    payload = JSON.parse(normalize.payload)
    assert_equal %w[request job host process runtime gc allocations spans_dropped spans].sort, payload.keys.sort
    assert_equal({ "method" => "POST", "path" => "/checkout", "request_id" => "7f3a9c1e-55d2-4c1a-9e0b-2d1f0a9b8c7d" }, payload["request"])
    json = normalize.payload
    %w[hunter2 deadbeef FALL25 abc123 secretpass sk_live mara@example.com arguments cookies params].each do |text|
      assert_not_includes json, text
    end
    http = payload["spans"].find { it["type"] == "http" }
    assert_equal [ "POST", "api.taxjar.com", "/v2/taxes" ], http.values_at("method", "host", "path")
  end

  test "spans: unknown types dropped, call sites made app-relative, context capped" do
    spans = JSON.parse(normalize.payload)["spans"]
    assert_equal %w[sql sql http view enqueue], spans.map { it["type"] }
    group = spans.second
    assert_equal [ 38, 1215.2 ], group.values_at("count", "span_ms")
    assert_equal "app/services/cart_total.rb", group.dig("call_site", "file")
    assert_equal 5, group.dig("call_site", "context", "lines").size
    assert_nil spans.first["count"], "single calls carry no count"
  end

  test "spans are capped and the excess counted" do
    spans = Array.new(Apm::Limits::SPANS + 5) { { type: "view", offset_ms: it, duration_ms: 1.0, template: "a.html.erb" } }
    payload = JSON.parse(normalize(trace_hash(spans:, spans_dropped: 2)).payload)
    assert_equal Apm::Limits::SPANS, payload["spans"].size
    assert_equal 7, payload["spans_dropped"]
  end

  test "jobs carry job details and no request; a missing id is generated as UUIDv7" do
    result = normalize(trace_hash(kind: "job", name: "Orders::PlaceJob", id: "nope", status: nil, failed: true,
                                  job: { adapter: "sidekiq", queue: "critical", queue_wait_ms: 12.5, executions: 2, arguments: [ "x" ] }))
    payload = JSON.parse(result.payload)
    assert_nil payload["request"]
    assert_equal({ "adapter" => "sidekiq", "queue" => "critical", "queue_wait_ms" => 12.5, "executions" => 2 }, payload["job"])
    assert Apm::TraceId.v7?(result.columns[:uuid])
    assert result.columns[:failed]
  end

  test "a status of 500 marks the trace failed" do
    assert normalize(trace_hash(status: 503)).columns[:failed]
  end
end
