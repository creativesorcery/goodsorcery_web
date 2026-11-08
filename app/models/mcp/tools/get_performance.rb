# get_performance: an app's Performance overview (Apm::Overview) for one
# environment, range and kind: the totals (rate, average, p75-p99, failure
# rate) and the endpoints or jobs by time consumed, with their Slower and
# N+1 flags and the slowest kept trace (for get_trace). Ranges past a day
# need the account's performance retention; a locked range is an error.
class Mcp::Tools::GetPerformance < Mcp::Tools::Base
  DEFAULT_LIMIT = 10
  KINDS = { "web" => "web", "job" => "jobs" }.freeze

  self.tool_name = "get_performance"
  self.title = "Get performance"
  self.scope = "read"
  self.captures_data = true
  self.annotations = READ_ONLY
  self.description = "Get an app's performance overview: totals (requests or runs per minute, average, p75, p90, p95, " \
                     "p99, failure rate) and the endpoints (kind web) or background jobs (kind job) taking the most " \
                     "time, with rate, percentiles, failure rate, share of time, Slower (p95 up vs. the past day) and " \
                     "N+1 flags, and the slowest kept trace id for get_trace."
  self.input_schema = {
    properties: {
      app: { type: "string", maxLength: 100, description: "An app slug from list_apps." },
      environment: { type: "string", maxLength: 32, description: "Defaults to the app's default or busiest environment." },
      range: { type: "string", enum: Apm::Range::KEYS, description: "Default 1d. 7d and 30d need enough performance retention." },
      kind: { type: "string", enum: KINDS.keys, description: "web (endpoints, the default) or job (background jobs)." },
      limit: limit_schema(default: DEFAULT_LIMIT, max: Apm::Overview::ROW_LIMIT)
    },
    required: %w[app], additionalProperties: false
  }

  private
    def project = @project ||= context.project!(arguments[:app])

    def selection
      @selection ||= Apm::Selection.new(project, { env: arguments[:environment], range: range_key, tab: KINDS.fetch(kind) },
                                        entitlements: context.entitlements)
    end

    def overview = @overview ||= Apm::Overview.new(project, checked_selection)

    def checked_selection
      requested = arguments[:environment]
      if requested.present? && !selection.environments.include?(requested)
        raise Mcp::NotFound, "No performance data for the environment #{Mcp::Text.quote(requested)} of #{project.slug}."
      end

      selection
    end

    def range_key
      key = arguments[:range].presence || Apm::Range::DEFAULT
      raise Mcp::InvalidArgument, "The #{key} range isn't available on this account." if Apm::Range.new(key).locked?(context.entitlements)

      key
    end

    def kind = KINDS.key?(arguments[:kind]) ? arguments[:kind] : "web"

    def build_payload
      return { app: project.slug, environments: [], transactions: [], note: "No performance data yet." } unless overview.any_data?

      { app: project.slug, environment: overview.environment, environments: selection.environments, range: selection.range.key,
        range_label: selection.range.label, kind:, totals: totals, transactions: rows }
    end

    def totals
      overview.tiles.to_h { |tile| [ tile.key, tile.value&.round(2) ] }
    end

    def rows
      @rows ||= overview.rows.first(limit(DEFAULT_LIMIT)).map { |row| Mcp::PerformanceRow.new(row, slowest_traces).to_h }
    end

    def slowest_traces
      @slowest_traces ||= ApmTrace.where(apm_transaction_id: overview.rows.map { |row| row.transaction.id })
        .since(selection.range.start).select("DISTINCT ON (apm_transaction_id) apm_transaction_id, uuid")
        .order(:apm_transaction_id, duration_ms: :desc).to_h { |trace| [ trace.apm_transaction_id, trace.uuid ] }
    end

    def text_lines
      return [ payload[:note] ] if payload[:note]

      [ "#{project.slug} · #{payload[:environment]} · #{payload[:range_label]} · #{kind}",
        "Totals: #{totals.map { |key, value| "#{key} #{value || '–'}" }.join(', ')}",
        *payload[:transactions].map { |row| Mcp::PerformanceRow.text_line(row) } ]
    end
end
