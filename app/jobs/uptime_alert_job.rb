# Sends one down or recovered alert (UptimeAlert) to the app's recipients.
# Enqueued by UptimeMonitor::Alerting after a check opens or resolves an
# incident. Arguments are the incident's integer id and the kind only, never
# the monitor's URL. A missing incident (the monitor was deleted) is dropped.
class UptimeAlertJob < ApplicationJob
  queue_as :alerts

  def perform(uptime_incident_id, kind)
    incident = UptimeIncident.includes(uptime_monitor: :project).find_by(id: uptime_incident_id)
    UptimeAlert.new(incident, kind).deliver if incident
  end
end
