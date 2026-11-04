# Hourly uptime rollups per monitor (UTC hours), written by
# UptimeMonitor::Checking#record_check with one upsert per check. Every query
# here is a single grouped query, however many monitors are asked for.
# Pruned after Ingest::Retention::UPTIME_ROLLUP_DAYS.
class UptimeHourlyCount < ApplicationRecord
  WINDOWS = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days }.freeze

  belongs_to :uptime_monitor, inverse_of: :hourly_counts

  class << self
    # { id => { "24h" => percent, "7d" => ..., "30d" => ... } }, each a Float
    # 0..100, or nil when the window has no checks. Windows end with the
    # current hour.
    def uptime_percentages(monitor_ids, now: Time.current)
      starts = window_starts(now)
      sums = starts.values.flat_map { |from| [ sum_since(:up_count, from), sum_since(:checks_count, from) ] }
      rows = where(uptime_monitor_id: monitor_ids, hour: starts.values.min..).group(:uptime_monitor_id).pluck(:uptime_monitor_id, *sums)
      by_id = rows.to_h { |id, *values| [ id, percentages(values) ] }
      monitor_ids.index_with { |id| by_id.fetch(id) { WINDOWS.keys.index_with { nil } } }
    end

    # { id => [[hour, checks, up], ...] } for the trailing hours, oldest first, zero-filled.
    def hourly_bars(monitor_ids, hours: 24, now: Time.current)
      from = TimeSeries.window_start(1.hour, hours, now:)
      rows = where(uptime_monitor_id: monitor_ids, hour: from..).pluck(:uptime_monitor_id, :hour, :checks_count, :up_count)
      by_id = rows.group_by(&:first)
      monitor_ids.index_with { |id| zero_filled(by_id.fetch(id, []), from, hours) }
    end

    # [[local day start, checks, up], ...] for the viewer's last `days` days, oldest first.
    def daily_bars(monitor, days: 30, zone: Time.zone)
      dates = (zone.today - (days - 1))..zone.today
      local_date = Arel.sql(sanitize_sql_array([ "DATE((hour AT TIME ZONE 'UTC') AT TIME ZONE ?)", zone.tzinfo.identifier ]))
      sums = where(uptime_monitor: monitor, hour: dates.first.in_time_zone(zone)..).group(local_date)
        .pluck(local_date, Arel.sql("SUM(checks_count)"), Arel.sql("SUM(up_count)")).to_h { |date, *counts| [ date, counts ] }
      dates.map { |date| [ date.in_time_zone(zone), *sums.fetch(date, [ 0, 0 ]).map(&:to_i) ] }
    end

    # { id => average ms of up checks since `since`, or nil }.
    def average_response_ms(monitor_ids, since:)
      rows = where(uptime_monitor_id: monitor_ids, hour: TimeSeries.align(since, 1.hour)..).group(:uptime_monitor_id)
        .pluck(:uptime_monitor_id, Arel.sql("SUM(response_time_ms_sum)"), Arel.sql("SUM(up_count)"))
      by_id = rows.to_h { |id, sum, up| [ id, up.to_i.positive? ? (sum.to_f / up).round : nil ] }
      monitor_ids.index_with { |id| by_id[id] }
    end

    private
      def window_starts(now)
        current_hour = TimeSeries.align(now, 1.hour)
        WINDOWS.transform_values { |span| current_hour - span + 1.hour }
      end

      def sum_since(column, from)
        Arel.sql(sanitize_sql_array([ "SUM(#{connection.quote_column_name(column)}) FILTER (WHERE hour >= ?)", from ]))
      end

      def percentages(values)
        WINDOWS.keys.zip(values.each_slice(2)).to_h do |window, (up, checks)|
          [ window, checks.to_i.positive? ? 100.0 * up.to_i / checks.to_i : nil ]
        end
      end

      def zero_filled(rows, from, hours)
        checks = TimeSeries.new(rows.to_h { |_, hour, count, _| [ hour, count ] }, from:, step: 1.hour, buckets: hours)
        ups = TimeSeries.new(rows.to_h { |_, hour, _, up| [ hour, up ] }, from:, step: 1.hour, buckets: hours).values
        checks.points.zip(ups).map { |(hour, count), up| [ hour, count, up ] }
      end
  end
end
