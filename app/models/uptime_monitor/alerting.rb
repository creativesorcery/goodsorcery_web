# Down and recovered alerts (docs/ARCHITECTURE.md §12.9). UptimeCheckJob calls
# #alert_later after record_check commits, with the incident and its kind
# ("monitor_down" or "monitor_recovered"). A stub until slice 4 replaces this
# file with UptimeAlertJob.perform_later(incident.id, kind).
module UptimeMonitor::Alerting
  def alert_later(incident, kind) = nil # Implemented by slice 4
end
