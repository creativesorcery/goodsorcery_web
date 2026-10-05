# Deletes stored data past its retention: occurrences older than their
# project's retention_days, and hourly rollups older than ROLLUP_DAYS.
class Ingest::Retention
  ROLLUP_DAYS = 90
  BATCH = 1_000

  def initialize(now: Time.current)
    @now = now
  end

  def prune
    prune_occurrences
    prune_rollups
  end

  # One batched delete per distinct retention period, not per project.
  def prune_occurrences
    Project.distinct.pluck(:retention_days).each do |days|
      Occurrence.where(project_id: Project.where(retention_days: days).select(:id))
        .where(received_at: ...(@now - days.days)).in_batches(of: BATCH).delete_all
    end
  end

  def prune_rollups
    cutoff = @now - ROLLUP_DAYS.days
    IssueHourlyCount.where(hour: ...cutoff).in_batches(of: BATCH).delete_all
    ProjectHourlyCount.where(hour: ...cutoff).in_batches(of: BATCH).delete_all
  end
end
