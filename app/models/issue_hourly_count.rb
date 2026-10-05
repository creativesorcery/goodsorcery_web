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
end
