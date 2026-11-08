# get_uptime: the uptime monitors of one app or all apps: name, host (never
# the URL, which may carry secrets), status, uptime over 24 hours, 7 and 30
# days, and open incidents. Read-only. Three queries: the monitors, their
# percentages and their open incidents.
class Mcp::Tools::GetUptime < Mcp::Tools::Base
  self.tool_name = "get_uptime"
  self.title = "Get uptime"
  self.scope = "read"
  self.annotations = READ_ONLY
  self.description = "Get the uptime monitors of an app (or of all apps): name, host, status (up, down, pending, paused), " \
                     "check interval, last check, uptime over 24h, 7d and 30d, and any open incident. Read-only."
  self.input_schema = {
    properties: { app: { type: "string", maxLength: 100, description: "An app slug from list_apps; all apps when left out." } },
    additionalProperties: false
  }

  private
    def monitors
      @monitors ||= begin
        project = context.optional_project(arguments[:app])
        scope = UptimeMonitor.where(project_id: project ? [ project.id ] : context.project_ids).order(:name, :id)
        context.attach_projects(scope.to_a)
      end
    end

    def build_payload
      { monitors: monitors.map { |monitor| present(monitor) } }
    end

    def present(monitor)
      { name: monitor.name, host: monitor.host, app: monitor.project.slug, status: monitor.paused? ? "paused" : monitor.status,
        interval_minutes: monitor.interval_minutes, last_checked_at: time(monitor.last_checked_at),
        down_since: time(monitor.down_since), uptime_percent: percentages.fetch(monitor.id),
        open_incident: incident(open_incidents[monitor.id]) }
    end

    def incident(incident)
      incident && { started_at: time(incident.started_at), cause: incident.cause_label }
    end

    def percentages = @percentages ||= UptimeHourlyCount.uptime_percentages(monitors.map(&:id))

    def open_incidents
      @open_incidents ||= UptimeIncident.open.where(uptime_monitor_id: monitors.map(&:id)).order(:id).index_by(&:uptime_monitor_id)
    end

    def text_lines
      return [ "No uptime monitors." ] if payload[:monitors].empty?

      payload[:monitors].map do |monitor|
        uptime = monitor[:uptime_percent].map { |window, value| "#{window} #{Mcp::Text.percent(value, percent: true)}" }.join(", ")
        incident = monitor[:open_incident] ? " · open incident since #{monitor[:open_incident][:started_at]} (#{monitor[:open_incident][:cause]})" : ""
        "#{monitor[:name]} (#{monitor[:host]}, app #{monitor[:app]}): #{monitor[:status]} · uptime #{uptime}#{incident}"
      end
    end
end
