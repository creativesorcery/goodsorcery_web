# Live updates after each check (docs/ARCHITECTURE.md §12.8). UptimeCheckJob
# calls #broadcast_checked once per check, so no debounce is needed. The
# broadcasts are pointers only (frame ids and paths on [project, :uptime]):
# each browser re-fetches the row or report with its own session, so the
# monitor's URL never reaches Action Cable or Redis.
module UptimeMonitor::Broadcasting
  def broadcast_checked
    LiveFrames.new(project).uptime_monitor_frames(self).each(&:reload)
  end
end
