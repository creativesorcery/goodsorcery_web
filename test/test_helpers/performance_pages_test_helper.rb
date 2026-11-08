require_relative "apm_fixture_stats"

# Support for the Performance page tests: transactions with a little data,
# extra traces, and statement counting.
module PerformancePagesTestHelper
  SECRET = "apm-fixture-secret".freeze

  # A listed transaction with one hourly and one minute row of `count`
  # requests in bucket 14 (85–125 ms), ten minutes ago.
  def create_apm_transaction(project, name, kind: "web", environment: "production", count: 5, **attributes)
    transaction = project.apm_transactions.create!(environment:, kind:, name:, first_seen_at: 1.day.ago, last_seen_at: 5.minutes.ago,
                                                    route: ("/#{name.underscore.tr('#', '/')}" if kind == "web"), http_method: ("GET" if kind == "web"),
                                                    **attributes)
    add_apm_stats(transaction, count:)
    transaction
  end

  def add_apm_stats(transaction, count:, minutes_ago: 10)
    minute = TimeSeries.align(minutes_ago.minutes.ago, 1.minute)
    row = ApmFixtureStats.columns(Apm::Distribution.from_buckets(count:, failed: 0, duration_ms: count * 100.0,
                                                                  buckets: [ [ 14, count, count * 40.0, 0.0, count * 30.0, count * 30.0 ] ]))
    ApmMinuteStat.insert!(row.merge(apm_transaction_id: transaction.id, minute:))
    ApmHourlyStat.insert!(row.merge(apm_transaction_id: transaction.id, hour: TimeSeries.align(minute, 1.hour)))
  end

  # A trace of the transaction `minutes_ago` minutes back (one per minute).
  def create_apm_trace(transaction, minutes_ago:, duration_ms: 300.0, payload: nil, **columns)
    minute = TimeSeries.align(minutes_ago.minutes.ago, 1.minute)
    started_at = minute + 5.seconds
    ApmTrace.create!(project: transaction.project, apm_transaction: transaction, uuid: Apm::TraceId.generate(started_at), minute:,
                     hour: TimeSeries.align(minute, 1.hour), started_at:, duration_ms:, db_ms: duration_ms / 2, ruby_ms: duration_ms / 2,
                     status: 200, payload: (payload || { request: { method: "GET", path: "/x" }, spans: [] }).to_json, **columns)
  end

  # Statements a request runs, without schema loads and query-cache hits.
  def count_request_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
