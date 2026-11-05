# Trims each closed hour to the ApmTrace::KEPT_PER_CLOSED_HOUR slowest traces
# per transaction (docs/ARCHITECTURE.md §13.4), for the LOOK_BACK closed
# hours before the current one (traces arrive up to 2 hours late). When runs
# were missed, it reaches further back, to the oldest hour (within the
# longest retention) that still has more than that many traces of one
# transaction. The open hour is never trimmed. Deletes at most BATCH ids per
# statement.
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
  end

  # Returns the number of traces deleted.
  def trim
    ApmTrace.uncached do
      @from = oldest_untrimmed_hour || (@to - LOOK_BACK)
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
    # The oldest hour before the look-back left untrimmed by missed runs.
    def oldest_untrimmed_hour
      before = @to - LOOK_BACK
      crowded = ApmTrace.select(:hour).where(hour: (before - Entitlements::MAX_APM_RETENTION_DAYS.days)...before)
        .group(:apm_transaction_id, :hour).having("COUNT(*) > ?", ApmTrace::KEPT_PER_CLOSED_HOUR)
      ApmTrace.from(crowded, :apm_traces).minimum(:hour)
    end

    def statement
      ApmTrace.sanitize_sql_array([ DELETE_SQL, { from: @from, to: @to, kept: ApmTrace::KEPT_PER_CLOSED_HOUR, batch: BATCH } ])
    end
end
