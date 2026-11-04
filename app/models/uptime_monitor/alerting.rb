# Down and recovered alerts (docs/ARCHITECTURE.md §12.9). UptimeCheckJob calls
# #alert_later after record_check commits, with the incident and its kind
# ("monitor_down" or "monitor_recovered"). The job gets ids and the kind only;
# UptimeAlert decides who is mailed when it runs.
module UptimeMonitor::Alerting
  def alert_later(incident, kind)
    UptimeAlertJob.perform_later(incident.id, kind.to_s)
  end
end
