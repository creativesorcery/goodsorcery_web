# The "Send test message" post from Settings › Alerts.
class SlackMessage::TestMessage < SlackMessage
  def initialize(project)
    @project = project
  end

  private
    attr_reader :project

    def fallback_text
      escape("Good Sorcery is connected: #{project.name} alerts will be posted here.")
    end

    def blocks
      [ section("*Good Sorcery is connected*\nAlerts for *#{escape(project.name)}* will be posted in this channel, " \
                "following the app's alert rules and environments."),
        button("Open alert settings", project_alerts_url(project)) ]
    end
end
