# The Slack section of Settings › Alerts: connects the app's channel (paste
# an incoming-webhook URL), replaces the URL, switches posting on or off, and
# disconnects. Like the rest of Settings › Alerts, any member of the account
# can change it; the page shows who pasted the URL and when.
#
# Pasting a URL always reconnects, even the one already saved (after fixing
# the channel in Slack, say): it switches posting on and clears a rejection.
#
# The webhook URL is a credential: filter_parameters (:url) keeps it out of
# request logs, the form never echoes it back, validation messages never
# include it, and the page shows only SlackConnection#masked_webhook_url.
class Projects::SlackConnectionsController < ApplicationController
  include ProjectScoped

  def update
    @slack_connection = @project.slack_connection || SlackConnection.new(project_id: @project.id)
    connecting = @slack_connection.new_record?

    if save_connection
      redirect_to project_alerts_path(@project, anchor: "slack"), notice: update_notice(connecting)
    else
      render "projects/alerts/show", status: :unprocessable_entity
    end
  end

  def destroy
    @project.slack_connection&.destroy!
    redirect_to project_alerts_path(@project, anchor: "slack"), notice: "Slack disconnected. Nothing more will be posted."
  end

  private
    def slack_connection_params
      params.expect(slack_connection: %i[webhook_url enabled])
    end

    def save_connection
      attributes = slack_connection_params
      @pasted = attributes.key?(:webhook_url)
      return @slack_connection.update(attributes) unless @pasted

      @slack_connection.paste_webhook_url(attributes[:webhook_url], by: Current.user)
    end

    def update_notice(connecting)
      return "Slack connected. Send a test message to check the channel." if connecting
      return "Slack webhook URL replaced." if @slack_connection.webhook_url_previously_changed?
      return "That webhook URL is the one already saved. Slack alerts are on." if @pasted

      @slack_connection.enabled? ? "Slack alerts turned on." : "Slack alerts turned off."
    end
end
