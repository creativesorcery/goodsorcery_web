# One endpoint or job of the Performance overview (Apm::Overview::Row) for
# get_performance: numbers and code identifiers only. Durations are in ms,
# rates per minute, failure rate and time share as fractions (0..1).
class Mcp::PerformanceRow
  def self.text_line(row)
    flags = [ ("Slower ×#{row[:slower_ratio]}" if row[:slower]), ("N+1" if row[:n_plus_one]) ].compact.join(", ")
    "#{row[:name]}#{" (#{row[:route]})" if row[:route]}: #{row[:rate_per_minute]}/min · avg #{Mcp::Text.ms(row[:average_ms])} · " \
      "p95 #{Mcp::Text.ms(row[:p95_ms])} · p99 #{Mcp::Text.ms(row[:p99_ms])} · failed #{Mcp::Text.percent(row[:failure_rate])} · " \
      "time share #{Mcp::Text.percent(row[:time_share])}#{" · #{flags}" if flags.present?}" \
      "#{" · slowest trace #{row[:slowest_trace]}" if row[:slowest_trace]}"
  end

  def initialize(row, slowest_traces)
    @row = row
    @figures = row.figures
    @slowest_traces = slowest_traces
  end

  def to_h
    { name: @row.transaction.name, route: @row.transaction.route_label, count: @figures.count,
      rate_per_minute: @row.rate.round(2), **durations, failure_rate: @figures.failed_rate&.round(4),
      time_share: @row.share.round(4), slower: @row.slower?, slower_ratio: @row.slower_ratio&.round(2),
      n_plus_one: @row.n_plus_one, slowest_trace: @slowest_traces[@row.transaction.id] }
  end

  private
    def durations
      { average_ms: @figures.average_ms&.round(1), p75_ms: @figures.p75&.round(1), p90_ms: @figures.p90&.round(1),
        p95_ms: @figures.p95&.round(1), p99_ms: @figures.p99&.round(1) }
    end
end
