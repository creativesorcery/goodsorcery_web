# A trace for get_trace (from Apm::TracePage): the layer split, the slowest
# MAX_SPANS spans (in timeline order), up to MAX_N_PLUS_ONE N+1 groups with
# call site, code and the generic preload hint, and the reported error.
# Spans are captured data (SQL is normalised, paths have no query strings).
class Mcp::TraceSummary
  MAX_SPANS = 40
  MAX_N_PLUS_ONE = 5

  def initialize(page, context)
    @page = page
    @context = context
    @trace = page.trace
  end

  def to_h
    @to_h ||= { id: @trace.uuid, title: Mcp::Captured.string(@page.title), transaction: transaction, started_at: Mcp::Text.time(@trace.started_at),
      duration_ms: @trace.duration_ms.round(1), status: @trace.status, failed: @trace.failed,
      layers: @page.layers.map { |layer, ms, share| { layer:, ms: ms.round(1), share: share.round(4) } },
      sql_count: @trace.sql_count, http_count: @trace.http_count, spans: spans, spans_total: @page.spans.size,
      spans_dropped: @page.spans_dropped, n_plus_one: n_plus_one, error_issue: @page.error_issue&.short_id,
      url: @context.trace_url(@trace) }
  end

  def text_lines
    data = to_h
    [ "#{data[:title]} · #{data[:transaction][:name]} · #{data[:transaction][:environment]} · #{data[:duration_ms]}ms at #{data[:started_at]}",
      "Layers: #{data[:layers].map { |layer| "#{layer[:layer]} #{layer[:ms]}ms (#{Mcp::Text.percent(layer[:share])})" }.join(', ')}",
      ("Reported error: #{data[:error_issue]}" if data[:error_issue]),
      "Slowest spans (#{data[:spans].size} of #{data[:spans_total]}):", *data[:spans].map { |span| span_line(span) },
      *data[:n_plus_one].flat_map { |group| n_plus_one_lines(group) } ]
  end

  private
    def transaction
      record = @page.transaction
      { name: record.name, route: record.route_label, kind: record.kind, environment: record.environment }
    end

    def spans
      @spans ||= @page.spans.max_by(MAX_SPANS) { |span| span.duration_ms.to_f }.sort_by { |span| span.offset_ms.to_f }.map { |span| span_hash(span) }
    end

    def span_hash(span)
      { type: span.type, layer: span.layer, offset_ms: span.offset_ms&.round(1), duration_ms: span.duration_ms&.round(1),
        count: span.count, label: Mcp::Captured.string(span_label(span), 500) }.compact
    end

    def span_label(span)
      return span.sql || span.name if span.type == "sql"
      return [ span.http_method, span.host, span.path, span.status ].compact.join(" ") if span.type == "http"

      span.template || span.job || span.name
    end

    def n_plus_one
      @n_plus_one ||= @page.details.n_plus_one_spans.first(MAX_N_PLUS_ONE).map do |span|
        hint = Apm::NPlusOneHint.new(span.sql)
        { sql: Mcp::Captured.string(span.sql, 500), calls: span.calls, total_ms: span.duration_ms.to_f.round(1),
          average_ms: span.average_ms.round(2), call_site: call_site(span.call_site), hint: [ hint.lead, hint.code ].compact.join(" ") }
      end
    end

    def call_site(site)
      return unless site

      lines = site.lines.each_with_index.map { |text, index| { line: site.start_line.to_i + index, text: Mcp::Captured.string(text, 200) } }
      { file: site.file, line: site.line, method: site.method_name, code: lines.first(11) }
    end

    def span_line(span) = "  +#{span[:offset_ms]}ms #{span[:duration_ms]}ms [#{span[:type]}#{" ×#{span[:count]}" if span[:count].to_i > 1}] #{span[:label]}"

    def n_plus_one_lines(group)
      site = group[:call_site]
      [ "N+1: #{group[:calls]} calls, #{group[:total_ms]}ms total: #{group[:sql]}",
        ("  at #{site[:file]}:#{site[:line]} in #{site[:method]}" if site),
        *Array(site&.dig(:code)).map { |code| "    #{code[:line].to_s.rjust(5)} | #{code[:text]}" }, "  #{group[:hint]}" ].compact
    end
end
