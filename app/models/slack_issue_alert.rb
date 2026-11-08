# One instant issue alert (new_issue, regression, reached_production or
# still_happening) for the app's Slack channel (docs/ARCHITECTURE.md §11.5).
# The Slack side of IssueAlert, run by the same IssueAlertJob, with the same
# send-time checks, and one post per event rather than one per recipient:
#
# - the app has an enabled Slack connection;
# - the app's rule for the kind is on;
# - the issue is still unresolved;
# - the scope covers the triggering occurrence's environment (or, without
#   one, any of the issue's environments);
# - still_happening: nothing was posted for the issue in the last 6 hours.
#
# #post_later claims a SlackDelivery (deduped, folded over the app's hourly
# cap) and enqueues SlackPostJob with its id. The job checks #still_due? again
# before posting.
#
#   SlackIssueAlert.new(issue, "regression", occurrence_id: 42).post_later
class SlackIssueAlert
  attr_reader :issue, :kind, :project

  def initialize(issue, kind, occurrence_id: nil, environments: IssueAlert::TriggeringEnvironments.new(issue, occurrence_id))
    @issue, @kind, @environments = issue, kind.to_s, environments
    @project = issue.project
  end

  def due?
    project.slack_alerts_enabled? && rule_on? && issue.unresolved? && project.alerts_cover?(@environments.to_a) && !throttled?
  end

  # When the post job runs: no occurrence then, so any of the issue's environments.
  def still_due?
    rule_on? && issue.unresolved? && project.alerts_cover?(issue.environments)
  end

  # Returns the delivery claimed (folded ones aren't posted now), or nil.
  def post_later
    return unless due?

    delivery = SlackDelivery.claim(project:, kind:, issue:)
    SlackPostJob.perform_later(delivery.id) if delivery&.sent?
    delivery
  end

  private
    def rule_on? = AlertRule::INSTANT_KINDS.include?(kind) && project.alert_rule_enabled?(kind)

    def throttled?
      kind == "still_happening" && SlackDelivery.posted_recently?(issue, kind)
    end
end
