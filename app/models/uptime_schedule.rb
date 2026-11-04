# Finds due monitors and enqueues one UptimeCheckJob each (docs/ARCHITECTURE.md
# §12.4). ScheduleUptimeChecksJob runs it every minute.
#
# A batch is claimed with one UPDATE ... RETURNING that bumps next_check_at:
# an overlapping run sees claimed rows as not due, and SKIP LOCKED keeps
# concurrent runs from waiting on each other. NO KEY UPDATE doesn't conflict
# with the key-share locks that check inserts take. The subquery reads the
# partial index index_uptime_monitors_due.
#
# Each monitor keeps its own schedule: next_check_at steps forward from its
# old minute in whole intervals until it is past now. A late claim (backlog,
# restart, deploy) never moves monitors onto the current minute, so monitors
# stay spread across their interval instead of bunching up. Minute alignment
# keeps a cron run that fires a little early from drifting a monitor.
class UptimeSchedule
  BATCH = 500

  CLAIM_SQL = <<~SQL.squish.freeze
    UPDATE uptime_monitors
    SET next_check_at = date_trunc('minute', next_check_at) + make_interval(mins => interval_minutes * (1 + CAST(floor(
      extract(epoch FROM CAST(:now AS timestamp) - date_trunc('minute', next_check_at)) / 60 / interval_minutes) AS integer)))
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
