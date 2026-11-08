# Turns one validated trace of a traces payload into a row
# (docs/ARCHITECTURE.md §13.5): plaintext columns (numbers, ids, status) and
# the encrypted JSON payload. Keys are allow-listed (anything else is
# dropped), strings capped and scrubbed again, spans capped at
# Apm::Limits::SPANS with the excess counted in spans_dropped.
class Apm::TraceNormalizer
  include Apm::JsonShape

  Result = Data.define(:kind, :name, :labels, :minute, :columns, :payload)
  # Column => payload keys, the first number wins. The app-code column keeps
  # its original name, ruby_ms, and older clients send that key too.
  LAYERS = { db_ms: %w[db_ms], http_ms: %w[http_ms], view_ms: %w[view_ms], ruby_ms: %w[app_ms ruby_ms] }.freeze

  def initialize(cleaner: Apm::TraceCleaner.new)
    @cleaner = cleaner
    @spans = Apm::SpanNormalizer.new(cleaner)
  end

  def normalize(trace)
    spans = Array(trace["spans"]).filter_map { @spans.normalize(it) }
    minute = minute(trace["minute"])
    Result.new(kind: trace["kind"], name: Apm::TransactionName.clean(trace["kind"], trace["name"]),
               labels: Apm::TransactionName.labels(trace, @cleaner), minute:,
               columns: columns(trace, minute, spans), payload: payload(trace, spans).to_json)
  end

  private
    def columns(trace, minute, spans)
      started_at = time(trace["started_at"])
      { uuid: Apm::TraceId.uuid(trace["id"]) || Apm::TraceId.generate(started_at), minute:,
        hour: TimeSeries.align(minute, 1.hour), started_at:, duration_ms: trace["duration_ms"].to_f,
        **layers(trace), **counts(trace, spans), **outcome(trace) }
    end

    def layers(trace) = LAYERS.transform_values { |keys| trace.values_at(*keys).find { number?(it) }.to_f }

    def counts(trace, spans)
      sql, http = spans.select { it["type"] == "sql" }, spans.select { it["type"] == "http" }
      { sql_count: count_or(trace["sql_count"]) { sql.sum { it["count"] || 1 } },
        http_count: count_or(trace["http_count"]) { http.sum { it["count"] || 1 } },
        n_plus_one_count: sql.count { it["count"].to_i >= Apm::N_PLUS_ONE_MIN } }
    end

    def count_or(value) = integer?(value, min: 0) ? [ value, 2**31 - 1 ].min : yield

    def outcome(trace)
      status = trace["status"]
      { status:, failed: trace["failed"] == true || status.to_i >= 500,
        error_event_uuid: Apm::TraceId.uuid(trace["error_event_id"]) }
    end

    def payload(trace, spans)
      { "request" => (request(trace["request"]) if trace["kind"] == "web"),
        "job" => (job(trace["job"]) if trace["kind"] == "job"),
        "host" => @cleaner.text(trace["host"], Apm::Limits::HOST),
        "process" => @cleaner.text(trace["process"], Apm::Limits::PROCESS),
        **environment(trace),
        "spans_dropped" => count_or(trace["spans_dropped"]) { 0 } + [ spans.size - Apm::Limits::SPANS, 0 ].max,
        "spans" => spans.first(Apm::Limits::SPANS) }
    end

    def request(request)
      return unless request.is_a?(Hash)

      { "method" => text(request["method"], Apm::Limits::HTTP_METHOD)&.upcase, "path" => @cleaner.path(request["path"]),
        "request_id" => @cleaner.text(request["request_id"], Apm::Limits::REQUEST_ID) }
    end

    def job(job)
      return unless job.is_a?(Hash)

      { "adapter" => text(job["adapter"], Apm::Limits::ADAPTER), "queue" => text(job["queue"], Apm::Limits::QUEUE),
        "queue_wait_ms" => (job["queue_wait_ms"] if number?(job["queue_wait_ms"])),
        "executions" => (job["executions"] if integer?(job["executions"], min: 0)) }
    end

    def environment(trace)
      runtime = RuntimeList.new(trace["runtime"]).to_a.map { it.merge("version" => @cleaner.text(it["version"], Apm::Limits::VERSION)) }
      gc = trace["gc"].is_a?(Hash) ? trace["gc"] : {}
      { "runtime" => runtime,
        "gc" => { "time_ms" => (gc["time_ms"] if number?(gc["time_ms"])), "count" => (gc["count"] if integer?(gc["count"], min: 0)) },
        "allocations" => (trace["allocations"] if integer?(trace["allocations"], min: 0)) }
    end
end
