# Sends one instant alert to the app's recipients (IssueAlert) and claims
# its post for the app's Slack channel (SlackIssueAlert, which enqueues
# SlackPostJob). Enqueued by ingest after commit for new_issue, regression and
# reached_production (with the triggering occurrence's id), and by
# StillHappeningCheck. Arguments are integer ids and the rule kind only, never
# captured data.
class IssueAlertJob < ApplicationJob
  queue_as :alerts

  def perform(issue_id, kind, occurrence_id = nil)
    issue = Issue.includes(project: :slack_connection).find_by(id: issue_id)
    return unless issue

    IssueAlert.new(issue, kind, occurrence_id:).deliver
    SlackIssueAlert.new(issue, kind, occurrence_id:).post_later
  end
end
