# "Send test message" in the Slack section of Settings › Alerts. Rate limited
# per user, and gated per connection by SlackConnection#claim_test_message
# (one per TEST_MESSAGE_GAP, whoever asks). The job takes the connection's id
# only, never the webhook URL.
class Projects::SlackConnections::TestMessagesController < ApplicationController
  include ProjectScoped

  rate_limit to: 5, within: 1.minute, by: -> { Current.user.id }, name: "slack_test_message", store: Ingest::RateLimitStore,
             with: -> { redirect_to project_alerts_path(@project, anchor: "slack"), alert: "Too many test messages. Try again in a minute." }

  def create
    redirect_to project_alerts_path(@project, anchor: "slack"), **test_outcome
  end

  private
    def test_outcome
      connection = @project.slack_connection || raise(ActiveRecord::RecordNotFound)
      gap = SlackConnection::TEST_MESSAGE_GAP.inspect
      return { alert: "A test message was sent less than #{gap} ago." } unless connection.claim_test_message

      SlackTestMessageJob.perform_later(connection.id)
      { notice: "Sending a test message to Slack. It should appear in the channel within a minute." }
    end
end
