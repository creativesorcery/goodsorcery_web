# Running a check and recording its outcome (docs/ARCHITECTURE.md §12.5).
# UptimeCheckJob runs the probe outside any transaction, then records:
#
#   incident, kind = monitor.record_check(monitor.run_check)
#   monitor.alert_later(incident, kind) if incident
#
# State machine (status → result → status, side effect, alert kind):
#   pending/up → up   → up      none
#   pending/up → down → down    down_since, opens an incident   monitor_down
#   down       → down → down    none (the incident stays open)
#   down       → up   → up      clears down_since, resolves it   monitor_recovered
#
# Flapping: going down again within flap_grace of the last incident's
# recovery reopens that incident instead of opening a new one, with no down
# alert. Each recovery still reports monitor_recovered, but alerts are
# deduped per incident, so a flapping monitor sends one down and one
# recovered email, not a pair per cycle (uptime alerts skip the hourly cap).
module UptimeMonitor::Checking
  FLAP_GRACE_INTERVALS = 3
  FLAP_GRACE_MAX = 30.minutes

  HOURLY_ON_DUPLICATE = <<~SQL.squish.freeze
    checks_count = uptime_hourly_counts.checks_count + 1,
    up_count = uptime_hourly_counts.up_count + EXCLUDED.up_count,
    response_time_ms_sum = uptime_hourly_counts.response_time_ms_sum + EXCLUDED.response_time_ms_sum
  SQL

  # One result; a failure is probed once more at once and the second result
  # kept. A refused address is not retried: it would only be refused again.
  def run_check(probe = UptimeProbe.new(url, monitor_id: id))
    result = probe.check
    return result if result.up? || result.error_kind == "blocked_address"

    probe.check
  end

  # Stores the check, its hourly rollup and the state transition in one
  # transaction under the monitor's row lock. `at` is when the check
  # started. Returns [incident, alert kind] when the monitor went down or
  # recovered, else nil. Records nothing when another check started at or
  # after unless_checked_since (the job's enqueued_at) got there first.
  def record_check(result, at: Time.current, unless_checked_since: nil)
    transaction do
      lock!("FOR NO KEY UPDATE")
      next if checked_since?(unless_checked_since)

      insert_check(result, at)
      count_check_hour(result, at)
      transition = transition_for(result, at)
      update_columns(state_after(result, at))
      transition
    end
  end

  # The "Check now" gate: true when the caller may enqueue a check. The cache
  # holds the monitor id only, and next_check_at is left alone.
  def check_soon
    gap = check_now_gap
    return false if paused? || checked_recently?(gap:)

    Rails.cache.write([ "uptime_check_now", id ], 1, unless_exist: true, expires_in: gap) ? true : false
  end

  # RECHECK_GAP, or the shortest interval the account is entitled to when
  # that is longer, so "Check now" can't check more often than the plan's
  # intervals allow.
  def check_now_gap
    return UptimeMonitor::RECHECK_GAP if entitlements.unlimited?

    [ UptimeMonitor::RECHECK_GAP, entitlements.uptime_intervals.min.minutes ].max
  end

  # Three intervals, at most 30 minutes.
  def flap_grace = [ (interval_minutes * FLAP_GRACE_INTERVALS).minutes, FLAP_GRACE_MAX ].min

  private
    def insert_check(result, at)
      UptimeCheck.insert({ uptime_monitor_id: id, checked_at: at, status: result.status, response_time_ms: result.response_time_ms,
                           http_status: result.http_status, error_kind: result.error_kind })
    end

    def count_check_hour(result, at)
      UptimeHourlyCount.upsert(
        { uptime_monitor_id: id, hour: TimeSeries.align(at, 1.hour), checks_count: 1, up_count: result.up? ? 1 : 0,
          response_time_ms_sum: result.up? ? result.response_time_ms.to_i : 0 },
        on_duplicate: Arel.sql(HOURLY_ON_DUPLICATE), record_timestamps: false
      )
    end

    def transition_for(result, at)
      return open_incident_for(result, at) if result.down? && !down?

      resolve_open_incident(at) if result.up? && down?
    end

    # An incident left open (say, by a hand-edited status) makes this a
    # down → down check, with no alert; ON CONFLICT on the one-open index
    # backs that up.
    def open_incident_for(result, at)
      return if incidents.open.exists? || reopen_flapping_incident(at)

      row = { uptime_monitor_id: id, started_at: at, error_kind: result.error_kind, http_status: result.http_status }
      inserted = UptimeIncident.insert(row, unique_by: :index_uptime_incidents_one_open, returning: %i[id])
      incident_id = inserted.rows.dig(0, 0)
      [ UptimeIncident.find(incident_id), "monitor_down" ] if incident_id
    end

    # Returns true when an incident resolved within flap_grace was reopened.
    # Its down and recovered emails were already sent, so none go out again.
    def reopen_flapping_incident(at)
      incident = incidents.where(resolved_at: (at - flap_grace)..).order(:resolved_at).last
      incident&.update_columns(resolved_at: nil) || false
    end

    def resolve_open_incident(at)
      incident = open_incident
      return unless incident

      incident.update_columns(resolved_at: at)
      [ incident, "monitor_recovered" ]
    end

    def state_after(result, at)
      { status: result.status, last_checked_at: at, last_response_time_ms: result.response_time_ms,
        last_http_status: result.http_status, last_error_kind: result.error_kind,
        down_since: result.up? ? nil : (down_since || at) }
    end
end
