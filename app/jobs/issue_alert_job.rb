# Sends one instant alert (IssueAlert) to the app's recipients. Enqueued by
# ingest after commit for new_issue, regression and reached_production (with
# the triggering occurrence's id), and by StillHappeningCheck. Arguments are
# integer ids and the rule kind only, never captured data.
class IssueAlertJob < ApplicationJob
  queue_as :alerts

  def perform(issue_id, kind, occurrence_id = nil)
    issue = Issue.includes(:project).find_by(id: issue_id)
    IssueAlert.new(issue, kind, occurrence_id:).deliver if issue
  end
end
