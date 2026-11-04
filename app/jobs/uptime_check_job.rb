# Checks one monitor (docs/ARCHITECTURE.md §12.5). The argument is the
# monitor's integer id only, never its URL. The probe runs outside any
# transaction; recording, alerting and the live update follow it.
#
# Skips a deleted or paused monitor, and one checked since this job was
# enqueued (Active Job's enqueued_at; ids stay the only argument). A backed-up
# queue holding several jobs for one monitor therefore probes it once, and a
# scheduled job and a "Check now" job running together record one check.
#
# The check is recorded at the time it started, so last_checked_at compares
# with enqueued_at however long the probe took.
class UptimeCheckJob < ApplicationJob
  queue_as :uptime

  # Deleted while its check ran; record_check's row lock finds nothing.
  discard_on ActiveRecord::RecordNotFound

  def perform(uptime_monitor_id)
    monitor = UptimeMonitor.includes(:project).find_by(id: uptime_monitor_id)
    return if monitor.nil? || monitor.paused? || monitor.checked_since?(enqueued_at)

    started_at = Time.current
    incident, kind = monitor.record_check(monitor.run_check, at: started_at, unless_checked_since: enqueued_at)
    monitor.alert_later(incident, kind) if incident
    monitor.broadcast_checked
  end
end
