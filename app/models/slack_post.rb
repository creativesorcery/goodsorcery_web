# Posts one claimed SlackDelivery to the app's channel, from SlackPostJob
# (docs/ARCHITECTURE.md §11.5). Checks again first: the connection is still
# enabled, the delivery wasn't posted already (a duplicate job), and the alert
# still qualifies (rule on, issue unresolved and in scope, or the incident
# still in its state). Then it reads the outcome:
#
# - delivered: posted_at is stamped;
# - rejected (Slack refused the webhook): the connection is turned off and
#   the owners are emailed once (SlackConnection#turn_off_after_rejection);
# - retry / failed: left to the job (retry, or give up).
#
#   SlackPost.new(delivery).deliver   # => SlackWebhook::Result, or nil when skipped
class SlackPost
  attr_reader :delivery

  def initialize(delivery)
    @delivery = delivery
  end

  def due?
    connection&.enabled? && !delivery.posted? && alert_still_due?
  end

  def deliver
    return unless due?

    SlackWebhook.new(connection.webhook_url).post(message.payload).tap { |result| record(result) }
  end

  private
    def connection = delivery.project.slack_connection

    def alert_still_due?
      return true if delivery.summary?
      return SlackUptimeAlert.new(delivery.uptime_incident, delivery.kind).still_due? if delivery.uptime_incident

      delivery.issue.present? && SlackIssueAlert.new(delivery.issue, delivery.kind).still_due?
    end

    def message
      return SlackMessage::Summary.new(delivery.project, delivery.summary_counts) if delivery.summary?
      return SlackMessage::UptimeAlert.new(delivery.uptime_incident, delivery.kind) if delivery.uptime_incident

      SlackMessage::IssueAlert.new(delivery.issue, delivery.kind)
    end

    def record(result)
      delivery.mark_posted if result.delivered?
      connection.turn_off_after_rejection(result.reason) if result.rejected?
    end
end
