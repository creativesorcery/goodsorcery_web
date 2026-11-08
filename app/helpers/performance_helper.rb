# The Performance pages (docs/ARCHITECTURE.md §13.9): number formats, chips,
# labels for transactions, traces and spans, and the SQL formatter. Trace
# payloads are captured data: everything here builds escaped tags with
# tag/safe_join, never raw or html_safe.
module PerformanceHelper
  LAYER_NAMES = { db: "Database", http: "External HTTP", view: "Rendering", app: "App code" }.freeze
  SPAN_TYPES = { "sql" => "SQL", "http" => "HTTP", "view" => "View", "enqueue" => "Job" }.freeze
  RANGE_SHORT = { "15m" => "15m", "1h" => "1h", "1d" => "24h", "7d" => "7d", "30d" => "30d" }.freeze
  SORT_LABELS = { "time" => "Time consumed", "p95" => "Slowest p95", "rate" => "Most requests", "failed" => "Most failed" }.freeze
  TABLE_GRID = "grid grid-cols-[minmax(280px,1fr)_76px_76px_76px_76px_76px_64px_150px_120px] items-center gap-4".freeze
  TRACE_GRID = "grid grid-cols-[130px_84px_84px_64px_128px_minmax(0,1fr)_64px] items-center gap-4".freeze
  TIMELINE_GRID = "grid grid-cols-[minmax(0,380px)_minmax(0,1fr)_72px] items-center gap-4".freeze

  # 0.4 → "0.4 ms", 412 → "412 ms", 1240 → "1.24 s", 3200 → "3.2 s"; nil → "—".
  def apm_duration(ms)
    value, unit = apm_duration_parts(ms)
    value ? "#{value} #{unit}" : "—"
  end

  # ["1.24", "s"] for the tiles, which set the unit smaller; [nil, nil] for nil.
  def apm_duration_parts(ms)
    return [ nil, nil ] if ms.nil?
    return [ apm_significant(ms), "ms" ] if apm_significant(ms).delete(",").to_f < 1000

    [ apm_significant(ms / 1000.0), "s" ]
  end

  # Per-minute rates: 1284.2 → "1,284", 4.46 → "4.5", 0.04 → "<0.1"; nil → "—".
  def apm_rate(value)
    return "—" if value.nil?
    return delimited(value.round) if value >= 10
    return "<0.1" if value.positive? && value < 0.05

    number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
  end

  # Fractions as percentages: 0.019 → "1.9%", 0.0024 → "0.24%", 0 → "0%"; nil → "—".
  def apm_percent(fraction)
    return "—" if fraction.nil?
    return "0%" if fraction.zero?

    percent = fraction * 100
    "#{number_with_precision(percent, precision: percent < 1 ? 2 : 1)}%"
  end

  # A tile's big figure: "412" with a smaller "ms", "0.24" with "%", or a rate.
  def apm_tile_value(format, value)
    return "—" if value.nil?

    number, unit = apm_value_parts(format, value)
    safe_join([ number, (tag.span(unit, class: "text-[0.56em] text-ink-300 #{'ml-1' if format == :duration}") if unit) ].compact)
  end

  # A figure as text: "164 ms", "0.31%", "1,310 per minute"; "—" for nil.
  def apm_figure(format, value)
    return "—" if value.nil?

    case format
    when :duration then apm_duration(value)
    when :percent then apm_percent(value)
    else "#{apm_rate(value)} per minute"
    end
  end

  def apm_sort_label(sort, web: true) = web ? SORT_LABELS.fetch(sort) : SORT_LABELS.fetch(sort).sub("requests", "runs")

  # 1.83 → "1.8×"
  def apm_ratio(ratio) = "#{number_with_precision(ratio, precision: 1)}×"

  def apm_slower_chip(small: true) = chip("Slower", tone: :coral, dot: true, small:)

  # "N+1 queries" on the overview; "N+1 ×38" on a timeline row.
  def apm_n_plus_one_chip(count = nil, small: true)
    chip(count ? "N+1 ×#{count}" : "N+1 queries", tone: :lilac, small:)
  end

  # The advice under a trace's N+1 detail: the same in every language.
  def apm_n_plus_one_advice(span, web:)
    "This query ran #{pluralize(delimited(span.calls), 'time')} in one #{web ? 'request' : 'job run'}. " \
      "Load the rows in one query (a join, an IN list or a batch load) instead of one per item."
  end

  # Web: "POST /checkout"; jobs: "sidekiq · critical · waits 0.8 s (p95)".
  def apm_route_line(transaction, queue_wait_ms: nil)
    return transaction.route_label if transaction.web?

    wait = queue_wait_ms && "waits #{apm_duration(queue_wait_ms)} (p95)"
    [ transaction.adapter, transaction.queue, wait ].compact_blank.join(" · ").presence
  end

  # "POST /checkout • app/controllers/checkouts_controller.rb" under an endpoint's name.
  def apm_source_line(transaction)
    first = transaction.web? ? transaction.route_label : [ transaction.adapter, transaction.queue ].compact_blank.join(" · ")
    [ first.presence, transaction.source_file.presence ].compact
  end

  # The table cell: "200"; jobs "OK" or "Failed".
  def apm_status_code(trace)
    return trace.status.to_s if trace.status

    trace.failed? ? "Failed" : "OK"
  end

  # "200 OK", "500 Internal Server Error"; jobs "OK" or "Failed".
  def apm_status_label(trace)
    return apm_status_code(trace) unless trace.status

    [ trace.status, Rack::Utils::HTTP_STATUS_CODES[trace.status] ].compact.join(" ")
  end

  def apm_failed_status?(trace) = trace.failed? || trace.status.to_i >= 500

  def apm_span_type(span) = SPAN_TYPES.fetch(span.type.to_s, span.type.to_s.capitalize)

  # 'SELECT "users" WHERE "id" = $1', "POST api.taxjar.com/v2/taxes",
  # "checkouts/create.html.erb" (any template or view name), "enqueue Orders::PlaceJob".
  def apm_span_label(span)
    case span.type
    when "sql" then apm_sql_label(span.sql.presence || span.name)
    when "http" then [ span.http_method, "#{span.host}#{span.path}" ].compact_blank.join(" ")
    when "view" then (span.template.presence || span.name).to_s
    when "enqueue" then "enqueue #{span.job}"
    else span.name.to_s
    end
  end

  def apm_sql_label(sql) = Apm::SqlSummary.new(sql).label

  # The statement one clause per line, keywords as .tok-k and placeholders
  # as .tok-n; every piece is escaped.
  def formatted_sql(sql)
    lines = Apm::SqlSummary.new(sql).lines.map { |line| safe_join(line.map { |type, text| apm_sql_token(type, text) }) }
    safe_join(lines, "\n")
  end

  # "14:32:08" today, "Nov 4 14:32:08" on other days, in the viewer's zone.
  def apm_clock(time)
    local = time.in_time_zone
    local.to_date == Time.zone.today ? local.strftime("%H:%M:%S") : local.strftime("%b %-d %H:%M:%S")
  end

  # "Requests · 24h" / "Runs · 7d"
  def apm_requests_label(transaction, range)
    "#{transaction.web? ? 'Requests' : 'Runs'} · #{RANGE_SHORT.fetch(range.key)}"
  end

  # "every 15 minutes", "every minute", "every 2 hours".
  def apm_bin_phrase(range)
    minutes = (range.bin / 60).to_i
    return "every minute" if minutes == 1
    return "every #{minutes} minutes" if minutes < 60

    "every #{pluralize(minutes / 60, 'hour')}".sub("every 1 hour", "every hour")
  end

  # [[label, value]] for the trace page's request (or job) panel.
  def apm_trace_facts(page)
    trace, details = page.trace, page.details
    facts = [ [ "Status", apm_status_label(trace) ], [ "Host", [ details.host, details.process ].compact_blank.join(" · ").presence || "—" ],
              [ "Started", trace.started_at.in_time_zone.strftime("%H:%M:%S.%L") ] ]
    facts += apm_job_facts(details.job) unless page.web?
    facts + [ [ "Runtime", apm_runtime(details.runtime) ], [ "GC", apm_gc(details.gc) ], [ "Allocations", apm_allocations(details.allocations) ] ]
  end

  private
    def apm_value_parts(format, value)
      case format
      when :duration then apm_duration_parts(value)
      when :percent then [ apm_percent(value).delete_suffix("%"), "%" ]
      else [ apm_rate(value), nil ]
      end
    end

    def apm_significant(value)
      number_with_precision(value, precision: 3, significant: true, strip_insignificant_zeros: true, delimiter: ",")
    end

    def apm_sql_token(type, text)
      case type
      when :keyword then tag.span(text, class: "tok-k")
      when :placeholder then tag.span(text, class: "tok-n")
      else text
      end
    end

    def apm_job_facts(job)
      job = job.is_a?(Hash) ? job : {}
      [ [ "Queue", [ job["adapter"], job["queue"] ].compact_blank.join(" · ").presence || "—" ],
        [ "Queue wait", apm_duration(job["queue_wait_ms"]) ] ]
    end

    def apm_runtime(runtime) = runtime.full_label || "—"

    def apm_gc(gc)
      return "—" unless gc["time_ms"] || gc["count"]

      [ (apm_duration(gc["time_ms"]) if gc["time_ms"]), (pluralize(gc["count"], "run") if gc["count"]) ].compact.join(" · ")
    end

    def apm_allocations(count) = count ? "#{compact_count(count)} objects" : "—"
end
