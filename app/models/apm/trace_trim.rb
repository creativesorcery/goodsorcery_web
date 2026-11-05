# Trims each closed hour to the ApmTrace::KEPT_PER_CLOSED_HOUR slowest traces
# per transaction (docs/ARCHITECTURE.md §13.4), for the LOOK_BACK closed
# hours before the current one (traces arrive up to 2 hours late). The open
# hour is never trimmed. Deletes at most BATCH ids per statement.
class Apm::TraceTrim
  LOOK_BACK = 3.hours
  BATCH = 1_000
  DELETE_SQL = <<~SQL.squish.freeze
    DELETE FROM apm_traces WHERE id IN (
      SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY apm_transaction_id, hour ORDER BY duration_ms DESC, id) AS rank
        FROM apm_traces WHERE hour >= CAST(:from AS timestamp) AND hour < CAST(:to AS timestamp)
      ) ranked
      WHERE rank > CAST(:kept AS integer)
      LIMIT CAST(:batch AS integer))
  SQL

  def initialize(now: Time.current)
    @to = TimeSeries.align(now, 1.hour)
    @from = @to - LOOK_BACK
  end

  # Returns the number of traces deleted.
  def trim
    ApmTrace.uncached do
      deleted = 0
      loop do
        count = ApmTrace.connection.delete(statement)
        deleted += count
        break if count < BATCH
      end
      deleted
    end
  end

  private
    def statement
      ApmTrace.sanitize_sql_array([ DELETE_SQL, { from: @from, to: @to, kept: ApmTrace::KEPT_PER_CLOSED_HOUR, batch: BATCH } ])
    end
end
