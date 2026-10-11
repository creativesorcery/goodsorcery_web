# The still_happening sweep (CheckStillHappeningJob, every 5 minutes): finds
# unresolved issues whose events in the trailing hour (IssueHourlyCount
# rollups) reach their app's threshold, in one query across every app with
# the rule on, and enqueues an IssueAlertJob for each one that is in the
# app's environment scope and wasn't alerted in the last 6 hours.
#
#   StillHappeningCheck.new.alert_hot_issues   # => the issues enqueued
class StillHappeningCheck
  KIND = "still_happening".freeze

  def initialize(now: Time.current)
    @now = now
  end

  def alert_hot_issues
    issues = alertable_issues
    ActiveJob.perform_all_later(issues.map { |issue| IssueAlertJob.new(issue.id, KIND) })
    issues
  end

  # Ignored and resolved issues are never hot. last_seen_at narrows the scan
  # to issues seen in the window ([project_id, status, last_seen_at] index).
  def hot_issue_ids
    since = IssueHourlyCount.trailing_hour_start(@now)
    Issue.unresolved.joins(project: :alert_rules).merge(AlertRule.enabled.still_happening)
      .joins(:hourly_counts).where(last_seen_at: since.., issue_hourly_counts: { hour: since.. })
      .group("issues.id", "alert_rules.threshold")
      .having([ "#{IssueHourlyCount::TRAILING_HOUR_SUM} >= alert_rules.threshold", IssueHourlyCount.trailing_hour_values(@now) ])
      .pluck("issues.id")
  end

  private
    def alertable_issues
      hot = hot_issue_ids
      ids = hot - recently_alerted(hot)
      return [] if ids.empty?

      Issue.includes(:project).where(id: ids).select { |issue| issue.project.alerts_cover?(issue.environments) }
    end

    def recently_alerted(ids)
      return [] if ids.empty?

      AlertDelivery.still_happening.where(issue_id: ids).since(@now - AlertDelivery::STILL_HAPPENING_WINDOW).distinct.pluck(:issue_id)
    end
end
