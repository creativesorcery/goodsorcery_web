# monitor_down or monitor_recovered for one incident: the monitor's name and
# host, never its URL (which may carry tokens).
class SlackMessage::UptimeAlert < SlackMessage
  def initialize(incident, kind)
    @incident, @kind = incident, kind.to_s
    @monitor = incident.uptime_monitor
    @project = @monitor.project
  end

  private
    attr_reader :incident, :kind, :monitor, :project

    def down? = kind == "monitor_down"

    def fallback_text
      escape(down? ? "Down: #{monitor.name} in #{project.name}" : "Recovered: #{monitor.name} in #{project.name} after #{duration}")
    end

    def blocks
      [ section("*#{escape(kind_label(kind))}* in *#{escape(project.name)}*\n#{headline}"),
        fields(details),
        button("Open monitor", project_uptime_monitor_url(project, monitor)) ]
    end

    def headline
      name = "*#{escape(monitor.name)}*"
      return "#{name} is down: Good Sorcery couldn't reach #{escape(monitor.host)}, even after an immediate retry." if down?

      "#{name} is back up after #{duration}."
    end

    def details
      [ [ "Host", escape(monitor.host) ], [ "Cause", escape(incident.cause_label) ],
        down? ? [ "Since", slack_time(incident.started_at) ] : [ "Back up", slack_time(incident.resolved_at) ],
        [ "Checks", escape(monitor.interval_label) ] ]
    end

    def duration = ApplicationController.helpers.uptime_duration(incident.duration)
end
