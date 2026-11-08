# Deletes stored data past its retention (run daily by goodsorcery:prune):
#
# - occurrences older than their project's retention_days (30, 60 or 90),
#   never more than Project::MAX_RETENTION_DAYS;
# - affected-user rows not seen within it, and tag values of issues not seen
#   within it (both hold captured personal data, encrypted or digested);
# - hourly rollups, one hour slice at a time: issue counts older than
#   ISSUE_ROLLUP_DAYS and project counts older than PROJECT_ROLLUP_DAYS;
# - inbound events that never processed within UNPROCESSED_TTL;
# - alert deliveries (throttle keys, ids only) older than AlertDelivery::KEPT_FOR,
#   except the down rows of uptime incidents still open;
# - uptime checks past their app's retention, never more than
#   UptimeCheck::MAX_KEPT_DAYS; uptime rollups older than UPTIME_ROLLUP_DAYS;
#   resolved uptime incidents older than UptimeIncident::KEPT_FOR;
# - performance data (#prune_apm): minute rows after ApmMinuteStat::KEPT_FOR;
#   hourly rows, traces and transactions not seen within each account's
#   apm_retention_days (a downgrade applies here); anything older than
#   Entitlements::MAX_APM_RETENTION_DAYS + 1 days as a backstop; inbound
#   performance batches after ApmInboundBatch::KEPT_FOR.
class Ingest::Retention
  # The issue chart's 30d view reaches back 30 local days; one more covers
  # any time zone offset. Nothing reads issue counts further back, so they
  # don't follow an app's longer retention.
  ISSUE_ROLLUP_DAYS = IssueHourlyCount::PERIODS.fetch("30d").fetch(:buckets) + 1
  # Project counts are totals per app and environment, with no captured data.
  # The issue list's 30d summary compares against the 30 days before (61 daily
  # buckets) and the monthly quota sums from the start of the UTC month.
  PROJECT_ROLLUP_DAYS = 90
  # Uptime percentages reach back 30 days and the daily bars 30 local days;
  # one more covers any time zone offset. Independent of error retention.
  UPTIME_ROLLUP_DAYS = UptimeReport::DAYS + 1
  APM_BACKSTOP_DAYS = Entitlements::MAX_APM_RETENTION_DAYS + 1
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
    prune_apm
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

  # The down rows of a still open incident stay: they pick who gets its
  # recovered email, however long the monitor has been down.
  def prune_alert_deliveries
    open_down_keys = UptimeIncident.open.select(Arel.sql("'monitor_down:' || id"))
    AlertDelivery.where(created_at: ...(@now - AlertDelivery::KEPT_FOR)).where.not(dedupe_key: open_down_keys)
      .in_batches(of: BATCH).delete_all
    prune_slack_deliveries
  end

  # Slack posts keep the same 30 days, and the down post of an open incident
  # stays for its recovered post.
  def prune_slack_deliveries
    SlackDelivery.where(created_at: ...(@now - AlertDelivery::KEPT_FOR))
      .where("uptime_incident_id IS NULL OR uptime_incident_id NOT IN (?)", UptimeIncident.open.select(:id))
      .in_batches(of: BATCH).delete_all
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

  def prune_apm
    prune_hour_slices(ApmMinuteStat, @now - ApmMinuteStat::KEPT_FOR, column: :minute)
    each_apm_retention_cutoff { |transaction_ids, cutoff| prune_apm_history(transaction_ids, cutoff) }
    prune_apm_backstop
    prune_apm_batches
  end

  # Whatever an account's value, nothing is kept past the longest retention.
  def prune_apm_backstop
    cutoff = rollup_cutoff(APM_BACKSTOP_DAYS)
    prune_hour_slices(ApmHourlyStat, cutoff)
    ApmTrace.where(hour: ...cutoff).in_batches(of: BATCH).delete_all
  end

  private
    # Accounts grouped by their resolved apm_retention_days (computed in
    # Ruby: hosted values live in a jsonb document), then one pass per value.
    def each_apm_retention_cutoff
      account_ids_by_days = Hash.new { |hash, days| hash[days] = [] }
      Account.find_each { |account| account_ids_by_days[account.entitlements.apm_retention_days] << account.id }
      account_ids_by_days.each do |days, account_ids|
        yield ApmTransaction.where(project_id: Project.where(account_id: account_ids).select(:id)), @now - days.days
      end
    end

    def prune_apm_history(transactions, cutoff)
      prune_hour_slices(ApmHourlyStat.where(apm_transaction_id: transactions.select(:id)), cutoff)
      ApmTrace.where(apm_transaction_id: transactions.select(:id), hour: ...cutoff).in_batches(of: BATCH).delete_all
      transactions.listed.where(last_seen_at: ...cutoff).in_batches(of: BATCH).delete_all
    end

    # Their jobs keep failing; the body is deleted unread and only ids are logged.
    def prune_apm_batches
      ApmInboundBatch.where(received_at: ...(@now - ApmInboundBatch::KEPT_FOR)).in_batches(of: BATCH) do |batch|
        unprocessed = batch.where(processed_at: nil).ids
        Rails.logger.info { "Retention deleted unprocessed APM batches #{unprocessed.join(', ')}" } if unprocessed.any?
        batch.delete_all
      end
    end

    # A value above the cap (set before it existed, or by hand) is pruned at the cap.
    def each_retention_cutoff(cap_days: Project::MAX_RETENTION_DAYS)
      Project.distinct.pluck(:retention_days).each do |days|
        yield Project.where(retention_days: days).select(:id), @now - [ days, cap_days ].min.days
      end
    end

    def rollup_cutoff(days) = TimeSeries.align(@now - days.days, 1.hour)

    # Deletes by time range (indexed), one hour slice per statement, never by
    # composite primary key. scope is a model or a relation.
    def prune_hour_slices(scope, cutoff, column: :hour)
      while (oldest = scope.where(column => ...cutoff).minimum(column))
        scope.where(column => oldest...[ oldest + 1.hour, cutoff ].min).delete_all
      end
    end
end
