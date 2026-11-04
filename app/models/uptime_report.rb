# A monitor's detail page (docs/ARCHITECTURE.md §12.8): uptime percentages,
# the 30-day bar in the viewer's local days, the 24-hour response times,
# recent checks and incidents. Each reader is one query, memoised.
class UptimeReport
  DAYS = 30
  RECENT_CHECKS = 20
  RECENT_INCIDENTS = 10

  attr_reader :monitor, :zone

  def initialize(monitor, zone: Time.zone, now: Time.current)
    @monitor = monitor
    @zone = zone
    @now = now
  end

  def percentages
    @percentages ||= UptimeHourlyCount.uptime_percentages([ monitor.id ], now: @now).fetch(monitor.id)
  end

  def daily_bars
    @daily_bars ||= UptimeHourlyCount.daily_bars(monitor, days: DAYS, zone:)
  end

  def average_response_ms
    return @average_response_ms if defined?(@average_response_ms)

    @average_response_ms = UptimeHourlyCount.average_response_ms([ monitor.id ], since: @now - 24.hours).fetch(monitor.id)
  end

  # [[bucket start, average ms], ...] of the last 24 hours, buckets with data only.
  def response_series
    @response_series ||= UptimeCheck.response_series(monitor, since: @now - 24.hours)
  end

  def recent_checks
    @recent_checks ||= monitor.checks.recent.limit(RECENT_CHECKS).to_a
  end

  # The open incident (however old) and those started within KEPT_FOR, newest first.
  def incidents
    @incidents ||= monitor.incidents.open.or(monitor.incidents.where(started_at: (@now - UptimeIncident::KEPT_FOR)..))
      .recent.limit(RECENT_INCIDENTS).to_a
  end

  def open_incident = incidents.find(&:open?)

  # When the current up run began: the last recovery, else the oldest rollup
  # kept (the monitor hasn't been down since then). Nil unless up.
  def up_since
    return unless monitor.up?

    incidents.reject(&:open?).filter_map(&:resolved_at).max || monitor.hourly_counts.minimum(:hour)
  end
end
