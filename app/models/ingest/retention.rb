# Deletes stored data past its retention (run daily by goodsorcery:prune):
#
# - occurrences older than their project's retention_days, never more than
#   Project::MAX_RETENTION_DAYS;
# - affected-user rows not seen within it, and tag values of issues not seen
#   within it (both hold captured personal data, encrypted or digested);
# - hourly rollups, one hour slice at a time: issue counts older than
#   ISSUE_ROLLUP_DAYS and project counts older than PROJECT_ROLLUP_DAYS;
# - inbound events that never processed within UNPROCESSED_TTL;
# - alert deliveries (throttle keys, ids only) older than AlertDelivery::KEPT_FOR;
# - uptime checks past their app's retention, never more than
#   UptimeCheck::MAX_KEPT_DAYS; uptime rollups older than UPTIME_ROLLUP_DAYS;
#   resolved uptime incidents older than UptimeIncident::KEPT_FOR.
class Ingest::Retention
  # The issue chart's 30d view reaches back 30 local days; one more covers
  # any time zone offset.
  ISSUE_ROLLUP_DAYS = Project::MAX_RETENTION_DAYS + 1
  # Project counts are totals per app and environment, with no captured data.
  # The issue list's 30d summary compares against the 30 days before (61 daily
  # buckets) and the monthly quota sums from the start of the UTC month.
  PROJECT_ROLLUP_DAYS = 90
  # Uptime percentages reach back 30 days and the daily bars 30 local days.
  UPTIME_ROLLUP_DAYS = Project::MAX_RETENTION_DAYS + 1
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
    prune_alert_deliveries
    prune_uptime
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
    prune_hour_slices(IssueHourlyCount, rollup_cutoff(ISSUE_ROLLUP_DAYS))
    prune_hour_slices(ProjectHourlyCount, rollup_cutoff(PROJECT_ROLLUP_DAYS))
  end

  # Their jobs keep failing; the body is deleted unread and only ids are logged.
  def prune_unprocessed
    InboundEvent.where(received_at: ...(@now - UNPROCESSED_TTL)).in_batches(of: BATCH) do |batch|
      Rails.logger.info { "Retention deleted unprocessed inbound events #{batch.ids.join(', ')}" }
      batch.delete_all
    end
  end

  def prune_alert_deliveries
    AlertDelivery.where(created_at: ...(@now - AlertDelivery::KEPT_FOR)).in_batches(of: BATCH).delete_all
  end

  # Raw checks feed only the 24h response series and the recent list; the
  # percentages and status bars read the rollups.
  def prune_uptime
    each_retention_cutoff(cap_days: UptimeCheck::MAX_KEPT_DAYS) do |project_ids, cutoff|
      monitor_ids = UptimeMonitor.where(project_id: project_ids).select(:id)
      UptimeCheck.where(uptime_monitor_id: monitor_ids, checked_at: ...cutoff).in_batches(of: BATCH).delete_all
    end
    prune_hour_slices(UptimeHourlyCount, rollup_cutoff(UPTIME_ROLLUP_DAYS))
    UptimeIncident.where(resolved_at: ...(@now - UptimeIncident::KEPT_FOR)).in_batches(of: BATCH).delete_all
  end

  private
    # A value above the cap (set before it existed, or by hand) is pruned at the cap.
    def each_retention_cutoff(cap_days: Project::MAX_RETENTION_DAYS)
      Project.distinct.pluck(:retention_days).each do |days|
        yield Project.where(retention_days: days).select(:id), @now - [ days, cap_days ].min.days
      end
    end

    def rollup_cutoff(days) = TimeSeries.align(@now - days.days, 1.hour)

    # Deletes by `hour` range (indexed), never by composite primary key.
    def prune_hour_slices(model, cutoff)
      while (oldest = model.where(hour: ...cutoff).minimum(:hour))
        model.where(hour: oldest...[ oldest + 1.hour, cutoff ].min).delete_all
      end
    end
end
