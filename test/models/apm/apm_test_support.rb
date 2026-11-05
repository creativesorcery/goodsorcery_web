# Payload builders for the performance ingest and processing tests.
module ApmTestSupport
  def current_minute = TimeSeries.align(Time.current, 1.minute)

  def metrics_transaction(name: "CheckoutsController#create", kind: "web", count: 3, buckets: nil, **overrides)
    buckets ||= [ [ 15, count - 1, 100.0, 50.0, 30.0, 20.0 ], [ 20, 1, 600.0, 400.0, 100.0, 100.0 ] ]
    base = { kind:, name:, count:, failed: 0, duration_ms: buckets.sum { it.drop(2).sum } }
    base.merge!(kind == "web" ? { method: "POST", route: "/checkout" } : { adapter: "sidekiq", queue: "critical" })
    base.merge(buckets:, **overrides)
  end

  def metrics_body(transactions = [ metrics_transaction ], minute: current_minute - 1.minute, batch_id: SecureRandom.uuid_v7, minutes: nil)
    minutes ||= [ { minute: minute.utc.iso8601, transactions: } ]
    { batch_id:, histogram: "gs-v1", notifier: { name: "goodsorcery-ruby", version: "0.2.0" }, minutes: }.to_json
  end

  def trace_hash(name: "CheckoutsController#create", duration_ms: 2940.2, minute: current_minute - 1.minute, **overrides)
    started_at = minute + 8.114.seconds
    { id: Apm::TraceId.generate(started_at), kind: "web", name:, method: "POST", route: "/checkout",
      minute: minute.utc.iso8601, started_at: started_at.utc.iso8601(3), duration_ms:,
      db_ms: 1220.4, http_ms: 1230.0, view_ms: 320.1, ruby_ms: 169.7, status: 200, failed: false, error_event_id: nil,
      request: { method: "POST", path: "/checkout?coupon=FALL25&token=abc123", request_id: "7f3a9c1e-55d2-4c1a-9e0b-2d1f0a9b8c7d",
                 params: { password: "hunter2" } },
      host: "web-2", process: "Puma worker 3", runtime: { ruby: "3.4.1", rails: "8.0.2" }, gc: { time_ms: 14.0, count: 3 },
      allocations: 1_400_000, sql_count: 43, http_count: 2, spans_dropped: 0, cookies: "_session=deadbeef",
      spans: sample_spans }.merge(overrides)
  end

  def sample_spans
    [ { type: "sql", offset_ms: 12.1, duration_ms: 3.0, name: "User Load", rows: 1,
        sql: "SELECT \"users\".* FROM \"users\" WHERE \"users\".\"email\" = 'mara@example.com' LIMIT 1" },
      { type: "sql", offset_ms: 40.1, duration_ms: 1180.0, span_ms: 1215.2, count: 38, rows: 38, name: "Product Load",
        sql: "SELECT \"products\".* FROM \"products\" WHERE \"products\".\"id\" = $1 LIMIT $2",
        call_site: { file: "/srv/app/releases/20261104/app/services/cart_total.rb", line: 27, method: "total_cents",
                     context: { start_line: 25, lines: [ "def total_cents", "  items.sum do |item|", "    item.product.price_cents", "  end", "end", "extra" ] } } },
      { type: "http", offset_ms: 1260.0, duration_ms: 550.0, method: "post", host: "user:secretpass@api.taxjar.com",
        path: "/v2/taxes?api_key=sk_live_123", status: 200 },
      { type: "view", offset_ms: 2560.3, duration_ms: 320.1, template: "checkouts/create.html.erb" },
      { type: "enqueue", offset_ms: 2900.0, duration_ms: 4.0, job: "Orders::PlaceJob", queue: "critical", arguments: [ 42 ] },
      { type: "bogus", offset_ms: 1.0, duration_ms: 1.0 } ]
  end

  def traces_body(traces = [ trace_hash ], batch_id: SecureRandom.uuid_v7)
    { batch_id:, notifier: { name: "goodsorcery-ruby", version: "0.2.0" }, traces: }.to_json
  end

  def store_batch(body, kind: "metrics", key: api_keys(:storefront_production), uuid: SecureRandom.uuid_v7)
    credential = ApiKey::Credential.new(key.id, key.project_id, key.environment, key.project.account_id)
    ApmInboundBatch.store(credential, kind:, uuid:, body:)
  end

  def process_batch(body, **options)
    Apm::BatchProcessor.new(store_batch(body, **options)).process
  end

  # Statements run, without transaction control (BEGIN, SAVEPOINT, …).
  def statements_in(&block)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless %w[TRANSACTION SCHEMA].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    statements
  end
end
