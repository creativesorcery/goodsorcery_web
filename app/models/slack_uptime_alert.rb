# A monitor_down or monitor_recovered alert for the app's Slack channel
# (docs/ARCHITECTURE.md §11.5): the Slack side of UptimeAlert, run by the same
# UptimeAlertJob, once per incident and kind.
#
# - the app has an enabled Slack connection and the rule for the kind is on;
# - monitor_down: the incident is still open; monitor_recovered: resolved,
#   and this incident's down alert was posted (or the down rule is off, so
#   none could be).
#
# Recorded with SlackDelivery.record, never .claim: like uptime emails,
# uptime posts skip the hourly cap and are never folded.
#
#   SlackUptimeAlert.new(incident, "monitor_down").post_later
class SlackUptimeAlert
  attr_reader :incident, :kind, :project

  def initialize(incident, kind)
    @incident, @kind = incident, kind.to_s
    @project = incident.uptime_monitor.project
  end

  def due?
    project.slack_alerts_enabled? && still_due? && (kind == "monitor_down" || down_posted_or_never_due?)
  end

  # Checked again when the post job runs.
  def still_due?
    AlertRule::UPTIME_KINDS.include?(kind) && incident_in_state? && project.alert_rule_enabled?(kind)
  end

  # Returns the delivery recorded, or nil (not due, or already posted).
  def post_later
    return unless due?

    delivery = SlackDelivery.record(project:, kind:, uptime_incident: incident)
    SlackPostJob.perform_later(delivery.id) if delivery
    delivery
  end

  private
    def incident_in_state?
      kind == "monitor_down" ? incident.open? : !incident.open?
    end

    def down_posted_or_never_due?
      !project.alert_rule_enabled?(:monitor_down) ||
        SlackDelivery.sent.exists?(project:, kind: "monitor_down", uptime_incident_id: incident.id)
    end
end
