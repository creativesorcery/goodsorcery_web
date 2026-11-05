# Stores a batch's traces (docs/ARCHITECTURE.md §13.4): the slowest per
# [transaction id, minute] is kept in Ruby, then one multi-row upsert on
# [apm_transaction_id, minute] in which a slower trace replaces the stored
# one (new uuid, payload and numbers) and a faster or equal one changes
# nothing. Rows are sorted by [transaction id, minute] (fixed lock order).
# upsert_all casts payload through the encrypted attribute type.
class Apm::TraceUpsert
  REPLACED = %w[project_id uuid hour started_at duration_ms db_ms http_ms view_ms ruby_ms sql_count http_count
                n_plus_one_count status failed error_event_uuid payload created_at].freeze
  ON_DUPLICATE = Arel.sql(REPLACED.map do |column|
    "#{column} = CASE WHEN EXCLUDED.duration_ms > apm_traces.duration_ms THEN EXCLUDED.#{column} ELSE apm_traces.#{column} END"
  end.join(", "))

  def initialize(project_id:, ids:, now: Time.current)
    @project_id = project_id
    @ids = ids
    @now = now
  end

  # traces: Apm::TraceNormalizer::Results. Returns the number of rows sent.
  def upsert(traces)
    rows = slowest(traces).sort_by { [ it[:apm_transaction_id], it[:minute] ] }
    return 0 if rows.empty?

    store(rows)
    rows.size
  end

  private
    def slowest(traces)
      traces.map { row(it) }.group_by { [ it[:apm_transaction_id], it[:minute] ] }.values
        .map { |same_minute| same_minute.max_by { it[:duration_ms] } }.uniq { it[:uuid] }
    end

    def row(trace)
      { project_id: @project_id, apm_transaction_id: @ids.fetch([ trace.kind, trace.name ]),
        **trace.columns, payload: trace.payload, created_at: @now }
    end

    # A trace id already stored for another minute (a client resending ids)
    # would break the [project_id, uuid] index: the rows then get fresh ids.
    def store(rows)
      ApmTrace.transaction(requires_new: true) { upsert_rows(rows) }
    rescue ActiveRecord::RecordNotUnique
      upsert_rows(rows.map { it.merge(uuid: Apm::TraceId.generate(it[:started_at])) })
    end

    def upsert_rows(rows)
      ApmTrace.upsert_all(rows, unique_by: %i[apm_transaction_id minute], on_duplicate: ON_DUPLICATE, record_timestamps: false)
    end
end
