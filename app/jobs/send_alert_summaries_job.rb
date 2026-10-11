# Hourly, just after the hour (config/schedule.yml): one "and N more alerts"
# email per user for the alerts folded over the hourly cap (AlertSummary).
class SendAlertSummariesJob < ApplicationJob
  queue_as :alerts

  def perform
    AlertSummary.deliver_due
  end
end
