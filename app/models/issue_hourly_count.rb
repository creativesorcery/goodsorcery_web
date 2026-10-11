class IssueHourlyCount < ApplicationRecord
  PERIODS = {
    "24h" => { step: 1.hour, buckets: 24 },
    "7d" => { step: 6.hours, buckets: 28 },
    "30d" => { step: 1.day, buckets: 30 }
  }.freeze

  belongs_to :issue, inverse_of: :hourly_counts

  # { issue_id => [count] * hours } for the trailing hours, in one query.
  def self.histograms(issue_ids, hours: 24)
    from = TimeSeries.window_start(1.hour, hours)
    rows = where(issue_id: issue_ids, hour: from..).pluck(:issue_id, :hour, :count)
    by_issue = rows.group_by(&:first).transform_values { |list| list.to_h { |_, hour, count| [ hour, count ] } }
    issue_ids.index_with { |id| TimeSeries.new(by_issue.fetch(id, {}), from:, step: 1.hour, buckets: hours).values }
  end

  # [[bucket_start, count], ...] for "24h" (hourly), "7d" (6-hourly) or "30d"
  # (days of `zone`, so each bar is a day as the viewer reads its label).
  def self.series(issue, period, zone: Time.zone)
    step, buckets = PERIODS.fetch(period.to_s, PERIODS["24h"]).values_at(:step, :buckets)
    return local_daily_series(issue, buckets, zone) if step == 1.day

    from = TimeSeries.window_start(step, buckets)
    counts = where(issue:, hour: from..).group(TimeSeries.bucket_sql(step)).sum(:count)
    TimeSeries.new(counts, from:, step:, buckets:).points
  end

  # Hourly rows grouped by the local date of their (UTC) hour, in one query.
  def self.local_daily_series(issue, days, zone)
    dates = (zone.today - (days - 1))..zone.today
    local_date = sanitize_sql_array([ "DATE((hour AT TIME ZONE 'UTC') AT TIME ZONE ?)", zone.tzinfo.identifier ])
    counts = where(issue:, hour: dates.first.in_time_zone(zone)..).group(Arel.sql(local_date)).sum(:count)
    dates.map { |date| [ date.in_time_zone(zone), counts.fetch(date, 0) ] }
  end
  private_class_method :local_daily_series

  # Events in the trailing 60 minutes, from hourly rows: the current clock
  # hour plus the not-yet-elapsed share of the previous one, evenly spread
  # (as ProjectHealth estimates it). Rows must start at .trailing_hour_start.
  TRAILING_HOUR_SUM = "SUM(CASE WHEN issue_hourly_counts.hour >= CAST(:current_hour AS timestamp) THEN issue_hourly_counts.count " \
                      "ELSE issue_hourly_counts.count * CAST(:previous_share AS double precision) END)".freeze

  def self.trailing_hour_start(now = Time.current) = TimeSeries.align(now, 1.hour) - 1.hour

  def self.trailing_hour_values(now = Time.current)
    { current_hour: TimeSeries.align(now, 1.hour), previous_share: 1 - TimeSeries.elapsed_fraction(1.hour, now:) }
  end

  # The estimate for one issue, e.g. for the still_happening email.
  def self.trailing_hour(issue, now: Time.current)
    sum = Arel.sql(sanitize_sql_array([ TRAILING_HOUR_SUM, trailing_hour_values(now) ]))
    where(issue:, hour: trailing_hour_start(now)..).pick(sum).to_f.round
  end
end
