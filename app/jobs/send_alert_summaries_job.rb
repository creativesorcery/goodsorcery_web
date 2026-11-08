# Hourly, just after the hour (config/schedule.yml): one "and N more alerts"
# email per user for the alerts folded over the hourly cap (AlertSummary),
# and one such Slack post per app for the posts folded over the app's Slack
# cap (SlackSummary).
class SendAlertSummariesJob < ApplicationJob
  queue_as :alerts

  def perform
    AlertSummary.deliver_due
    SlackSummary.post_due
  end
end
