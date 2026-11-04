# One down or recovered alert about one incident of an uptime monitor,
# decided and handed to the mailer for each recipient (ARCHITECTURE.md §12.9).
#
# UptimeCheckJob only reports the transition (UptimeMonitor::Alerting enqueues
# UptimeAlertJob with the incident id and kind). Everything is decided here,
# at send time:
#
# - the app's rule for the kind is on (the environment scope doesn't apply);
# - monitor_down: the incident is still open; monitor_recovered: resolved.
#
# Recipients are verified members who haven't muted the app's uptime alerts.
# A recovered email only goes to those who were sent this incident's down
# email. Each gets one AlertDelivery.record per incident and kind: never
# .claim, so uptime alerts skip the hourly cap and are never folded into the
# summary.
#
#   UptimeAlert.new(incident, "monitor_down").deliver   # => users mailed
class UptimeAlert
  attr_reader :incident, :kind, :project

  def initialize(incident, kind)
    @incident, @kind = incident, kind.to_s
    @project = incident.uptime_monitor.project
  end

  def due?
    AlertRule::UPTIME_KINDS.include?(kind) && incident_in_state? && project.alert_rule_enabled?(kind)
  end

  # Returns the users it was mailed to (a used key mails nobody).
  def deliver
    return [] unless due?

    recipients.select { |user| deliver_to(user) }
  end

  private
    def incident_in_state?
      kind == "monitor_down" ? incident.open? : !incident.open?
    end

    def recipients
      users = project.uptime_alert_recipients
      return users if kind == "monitor_down"

      users.where(id: down_deliveries.select(:user_id))
    end

    # Narrowed by app, kind and key; rows are kept for AlertDelivery::KEPT_FOR.
    def down_deliveries
      AlertDelivery.sent.where(project:, kind: "monitor_down", dedupe_key: AlertDelivery.incident_key("monitor_down", incident))
    end

    def deliver_to(user)
      return false unless AlertDelivery.record(user:, project:, kind:, dedupe_key: AlertDelivery.incident_key(kind, incident))

      AlertsMailer.public_send(kind, user, incident).deliver_later
      true
    end
end
