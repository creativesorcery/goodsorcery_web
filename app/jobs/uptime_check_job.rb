# Checks one monitor (docs/ARCHITECTURE.md §12.5). The argument is the
# monitor's integer id only, never its URL. The probe runs outside any
# transaction; recording, alerting and the live update follow it.
#
# Skips a deleted or paused monitor, and one checked within RECHECK_GAP, so a
# backed-up queue can't run the same monitor twice in a row.
class UptimeCheckJob < ApplicationJob
  queue_as :uptime

  # Deleted while its check ran; record_check's row lock finds nothing.
  discard_on ActiveRecord::RecordNotFound

  def perform(uptime_monitor_id)
    monitor = UptimeMonitor.includes(:project).find_by(id: uptime_monitor_id)
    return if monitor.nil? || monitor.paused? || monitor.checked_recently?

    incident, kind = monitor.record_check(monitor.run_check)
    monitor.alert_later(incident, kind) if incident
    monitor.broadcast_checked
  end
end
