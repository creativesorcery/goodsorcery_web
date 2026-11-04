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
module UptimeMonitor::Checking
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
  # transaction under the monitor's row lock. Returns [incident, alert kind]
  # when the monitor went down or recovered, else nil.
  def record_check(result, at: Time.current)
    transaction do
      lock!("FOR NO KEY UPDATE")
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
    return false if paused? || checked_recently?

    Rails.cache.write([ "uptime_check_now", id ], 1, unless_exist: true, expires_in: UptimeMonitor::RECHECK_GAP) ? true : false
  end

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

    # ON CONFLICT on the one-open index: an incident left open (say, by a
    # hand-edited status) makes this a down → down check, with no alert.
    def open_incident_for(result, at)
      row = { uptime_monitor_id: id, started_at: at, error_kind: result.error_kind, http_status: result.http_status }
      inserted = UptimeIncident.insert(row, unique_by: :index_uptime_incidents_one_open, returning: %i[id])
      incident_id = inserted.rows.dig(0, 0)
      [ UptimeIncident.find(incident_id), "monitor_down" ] if incident_id
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
