# Deletes stored data past its retention (run daily by goodsorcery:prune):
#
# - occurrences older than their project's retention_days;
# - affected-user rows not seen within it, and tag values of issues not seen
#   within it (both hold captured personal data, encrypted or digested);
# - hourly rollups older than ROLLUP_DAYS, one hour slice at a time;
# - inbound events that never processed within UNPROCESSED_TTL.
class Ingest::Retention
  ROLLUP_DAYS = 90
  UNPROCESSED_TTL = 1.day
  BATCH = 1_000

  def initialize(now: Time.current)
    @now = now
  end

  def prune
    prune_occurrences
    prune_issue_data
    prune_rollups
    prune_unprocessed
  end

  # One batched delete per distinct retention period, not per project.
  def prune_occurrences
    each_retention_cutoff do |project_ids, cutoff|
      Occurrence.where(project_id: project_ids, received_at: ...cutoff).in_batches(of: BATCH).delete_all
    end
  end

  def prune_issue_data
    each_retention_cutoff do |project_ids, cutoff|
      IssueUser.where(project_id: project_ids, last_seen_at: ...cutoff).in_batches(of: BATCH).delete_all
      Issue.where(project_id: project_ids, last_seen_at: ...cutoff).in_batches(of: BATCH) do |issues|
        IssueTagCount.where(issue_id: issues.select(:id)).delete_all
      end
    end
  end

  def prune_rollups
    cutoff = TimeSeries.align(@now - ROLLUP_DAYS.days, 1.hour)
    prune_hour_slices(IssueHourlyCount, cutoff)
    prune_hour_slices(ProjectHourlyCount, cutoff)
  end

  # Their jobs keep failing; the body is deleted unread and only ids are logged.
  def prune_unprocessed
    InboundEvent.where(received_at: ...(@now - UNPROCESSED_TTL)).in_batches(of: BATCH) do |batch|
      Rails.logger.info { "Retention deleted unprocessed inbound events #{batch.ids.join(', ')}" }
      batch.delete_all
    end
  end

  private
    def each_retention_cutoff
      Project.distinct.pluck(:retention_days).each do |days|
        yield Project.where(retention_days: days).select(:id), @now - days.days
      end
    end

    # Deletes by `hour` range (indexed), never by composite primary key.
    def prune_hour_slices(model, cutoff)
      while (oldest = model.where(hour: ...cutoff).minimum(:hour))
        model.where(hour: oldest...[ oldest + 1.hour, cutoff ].min).delete_all
      end
    end
end
