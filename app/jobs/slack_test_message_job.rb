# "Send test message" from Settings › Alerts: posts SlackMessage::TestMessage
# once, without retries. A webhook Slack rejects is turned off (and the owners
# emailed) like any other post. The argument is the connection's id only.
class SlackTestMessageJob < ApplicationJob
  queue_as :alerts

  def perform(slack_connection_id)
    connection = SlackConnection.includes(:project).find_by(id: slack_connection_id)
    return unless connection

    result = SlackWebhook.new(connection.webhook_url).post(SlackMessage::TestMessage.new(connection.project).payload)
    connection.turn_off_after_rejection(result.reason) if result.rejected?
    logger.info("SlackTestMessageJob connection=#{connection.id} outcome=#{result.outcome} status=#{result.log_label}")
  end
end
