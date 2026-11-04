# Finds due monitors and enqueues one UptimeCheckJob each (docs/ARCHITECTURE.md
# §12.4). ScheduleUptimeChecksJob runs it every minute.
#
# A batch is claimed with one UPDATE ... RETURNING that bumps next_check_at:
# an overlapping run sees claimed rows as not due, and SKIP LOCKED keeps
# concurrent runs from waiting on each other. NO KEY UPDATE doesn't conflict
# with the key-share locks that check inserts take. Next checks align to the
# minute so a cron run firing a little early doesn't drift a monitor by one
# run. The subquery reads the partial index index_uptime_monitors_due.
class UptimeSchedule
  BATCH = 500

  CLAIM_SQL = <<~SQL.squish.freeze
    UPDATE uptime_monitors
    SET next_check_at = date_trunc('minute', CAST(:now AS timestamp)) + make_interval(mins => interval_minutes)
    WHERE id IN (
      SELECT id FROM uptime_monitors
      WHERE paused_at IS NULL AND next_check_at <= CAST(:now AS timestamp)
      ORDER BY next_check_at
      LIMIT :batch
      FOR NO KEY UPDATE SKIP LOCKED)
    RETURNING id
  SQL

  def self.enqueue_due(now: Time.current) = new(now:).enqueue_due

  def initialize(now: Time.current, batch: BATCH)
    @now = now
    @batch = batch
  end

  # Returns how many checks were enqueued. Job arguments are ids only.
  def enqueue_due
    enqueued = 0
    loop do
      ids = claim_batch
      ActiveJob.perform_all_later(ids.map { |id| UptimeCheckJob.new(id) }) if ids.any?
      enqueued += ids.size
      return enqueued if ids.size < @batch
    end
  end

  # Uncached: an UPDATE ... RETURNING must never be answered from the query cache.
  def claim_batch
    sql = UptimeMonitor.sanitize_sql([ CLAIM_SQL, { now: @now.utc, batch: @batch } ])
    UptimeMonitor.uncached { UptimeMonitor.connection.select_values(sql) }
  end
end
