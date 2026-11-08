# Sends one down or recovered alert to the app's recipients (UptimeAlert)
# and claims its post for the app's Slack channel (SlackUptimeAlert).
# Enqueued by UptimeMonitor::Alerting after a check opens or resolves an
# incident. Arguments are the incident's integer id and the kind only, never
# the monitor's URL. A missing incident (the monitor was deleted) is dropped.
class UptimeAlertJob < ApplicationJob
  queue_as :alerts

  def perform(uptime_incident_id, kind)
    incident = UptimeIncident.includes(uptime_monitor: { project: :slack_connection }).find_by(id: uptime_incident_id)
    return unless incident

    UptimeAlert.new(incident, kind).deliver
    SlackUptimeAlert.new(incident, kind).post_later
  end
end
