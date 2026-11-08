# Sends one instant alert to the app's recipients (IssueAlert) and claims
# its post for the app's Slack channel (SlackIssueAlert, which enqueues
# SlackPostJob). Enqueued by ingest after commit for new_issue, regression and
# reached_production (with the triggering occurrence's id), and by
# StillHappeningCheck. Arguments are integer ids and the rule kind only, never
# captured data. Both share one TriggeringEnvironments, so the triggering
# occurrence is looked up at most once.
class IssueAlertJob < ApplicationJob
  queue_as :alerts

  def perform(issue_id, kind, occurrence_id = nil)
    issue = Issue.includes(project: :slack_connection).find_by(id: issue_id)
    return unless issue

    environments = IssueAlert::TriggeringEnvironments.new(issue, occurrence_id)
    IssueAlert.new(issue, kind, environments:).deliver
    SlackIssueAlert.new(issue, kind, environments:).post_later
  end
end
