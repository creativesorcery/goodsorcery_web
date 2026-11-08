# The Uptime pages (docs/ARCHITECTURE.md §12.8): status chips, number
# formatting and the server-rendered SVG status bar. Only names, hosts,
# numbers and times reach these helpers, never a monitor's URL.
module UptimeHelper
  # Below md a row is a card: name and status, then the uptime figures
  # (labelled, as the header row is hidden) with the check time in the name cell.
  ROW_GRID = "grid grid-cols-[minmax(0,1fr)_auto] md:grid-cols-[124px_minmax(0,1fr)_80px_204px] " \
    "xl:grid-cols-[124px_minmax(0,1fr)_118px_80px_76px_204px_170px] items-center gap-x-3 gap-y-2 md:gap-4".freeze
  WIDE_CELL = "hidden xl:block".freeze
  COLUMN_CELL = "max-md:hidden".freeze
  MOBILE_ONLY = "md:hidden".freeze
  BAR_SLOT = 6
  HOURLY_TITLE = "%b %-d, %H:%M".freeze
  DAILY_TITLE = "%b %-d".freeze
  UP_COLORS = { all: [ ChartHelper::MINT, 1 ], most: [ ChartHelper::CORAL, 0.55 ], few: [ ChartHelper::CORAL, 1 ],
                none: [ ChartHelper::PAPER, 0.45 ] }.freeze

  ERROR_ATTRIBUTE_LABELS = { url: "URL", name: "Name", interval_minutes: "Check interval" }.freeze

  # [[label, minutes], ...] for the interval select. Locked intervals (hosted
  # only) read "Every minute · Upgrade to unlock", or "Every minute · Coming
  # soon" without an upgrade URL, with that note as their title too; the
  # form disables them. Native select popups don't show option titles in
  # most browsers, so the visible label suffix carries the note and the hint
  # below the select carries the hover title (#uptime_locked_intervals_hint_tag).
  def uptime_interval_options
    locked = entitlements.locked_uptime_intervals
    UptimeMonitor::INTERVAL_LABELS.map do |minutes, label|
      locked.include?(minutes) ? [ "#{label} · #{locked_note}", minutes, { title: locked_note } ] : [ label, minutes ]
    end
  end

  # The hint below the interval select when some intervals are locked
  # (hosted only), the select's aria-describedby. Without an upgrade URL it
  # is titled "Coming soon", the hover tooltip the locked options themselves
  # can't show inside a native select popup.
  def uptime_locked_intervals_hint_tag
    tag.p uptime_locked_intervals_hint, id: "uptime_monitor_interval_hint", class: "hint",
      title: (UpgradeOffer::COMING_SOON unless upgrade_offered?)
  end

  def uptime_locked_intervals_hint
    return "Some intervals are coming soon." unless upgrade_offered?

    safe_join([ "Some intervals aren't available on this account.", upgrade_to_unlock ], " ")
  end

  # Whole sentences: "URL must be a public http:// or https:// address." The
  # messages never repeat the URL.
  def uptime_monitor_error_sentences(monitor)
    monitor.errors.map do |error|
      sentence = error.attribute == :base ? error.message : "#{ERROR_ATTRIBUTE_LABELS.fetch(error.attribute, error.attribute.to_s.humanize)} #{error.message}"
      sentence.end_with?(".") ? sentence : "#{sentence}."
    end
  end

  # Why a monitor is paused. Only hosted mode pauses monitors (over its
  # app's monitor limit); a self-hosted instance that used to be hosted
  # resumes them with the fit task.
  def uptime_paused_note
    return safe_join([ "Over this app's monitor limit.", upgrade_to_unlock ].compact, " ") unless entitlements.unlimited?

    safe_join([ "Paused while this instance was hosted. Run", tag.code("bin/rails goodsorcery:fit_entitlements", class: "font-mono"),
                "to resume it." ], " ")
  end

  # "Up" (mint), "Down" (coral, pulsing) with how long, "Pending" or "Paused" (muted).
  def uptime_status_chip(monitor, small: false)
    return chip("Paused", tone: :muted, small:) if monitor.paused?
    return chip("Up", tone: :mint, small:) if monitor.up?
    return chip(uptime_down_label(monitor), tone: :coral, dot: true, small:) if monitor.down?

    chip "Pending", tone: :muted, small:
  end

  def uptime_check_chip(check)
    check.up? ? chip("Up", tone: :mint, small: true) : chip("Down", tone: :coral, small: true)
  end

  # 99.93 → "99.93%", 100.0 → "100%", nil → "—". Rounded down, so a single
  # failed check never shows as 100%.
  def uptime_percent(value)
    return "—" if value.nil?

    "#{number_with_precision(value.to_f.floor(2), precision: 2, strip_insignificant_zeros: true)}%"
  end

  # 212 → "212 ms", 1840 → "1,840 ms", nil → "—".
  def uptime_ms(value)
    value.nil? ? "—" : "#{number_with_delimiter(value.round)} ms"
  end

  # 40 → "40 s", 840 → "14 min", 7_500 → "2h 5m", 97_200 → "1d 3h".
  def uptime_duration(seconds)
    seconds = seconds.to_i
    return "#{seconds} s" if seconds < 1.minute
    return "#{seconds / 1.minute} min" if seconds < 1.hour
    return "#{seconds / 1.hour}h #{seconds % 1.hour / 1.minute}m" if seconds < 1.day

    "#{seconds / 1.day}d #{seconds % 1.day / 1.hour}h"
  end

  # One segment per bucket ([start, checks, up]), each with a <title> such as
  # "Oct 3, 14:00 · 98.3% up · 60 checks". Pure SVG, stretched to its box.
  def uptime_bar_svg(buckets, height: 22, title_format: HOURLY_TITLE, period: "Last 24 hours")
    width = [ buckets.size, 1 ].max * BAR_SLOT
    segments = buckets.each_with_index.map { |bucket, index| uptime_bar_segment(bucket, index, height, title_format) }
    tag.svg safe_join(segments), width: "100%", height:, viewBox: "0 0 #{width} #{height}", preserveAspectRatio: "none",
      class: "block", role: "img", "aria-label": uptime_bar_label(buckets, period)
  end

  def uptime_daily_bar_svg(buckets, height: 34)
    uptime_bar_svg(buckets, height:, title_format: DAILY_TITLE, period: "Last #{buckets.size} days")
  end

  # "Last 24 hours: 99.3% up" (or "no checks"), for screen readers.
  def uptime_bar_label(buckets, period)
    checks = buckets.sum { |_, count, _| count.to_i }
    up = buckets.sum { |_, _, count| count.to_i }
    "#{period}: #{checks.zero? ? 'no checks' : "#{uptime_percent(100.0 * up / checks)} up"}"
  end

  # The 24h response-time sparkline, or nil when no check was up.
  def uptime_response_sparkline(series)
    return if series.empty?

    sparkline_svg series.map(&:last), color: ChartHelper::IRIS, width: 600, height: 56, fluid: true
  end

  private
    def uptime_down_label(monitor)
      monitor.down_since ? "Down for #{uptime_duration(Time.current - monitor.down_since)}" : "Down"
    end

    def uptime_bar_segment((time, checks, up), index, height, title_format)
      color, opacity = UP_COLORS.fetch(uptime_share(checks, up))
      tag.rect tag.title(uptime_segment_title(time, checks, up, title_format)),
        x: index * BAR_SLOT, width: BAR_SLOT - 1.5, height:, rx: 1.5, fill: color, opacity:
    end

    def uptime_share(checks, up)
      return :none if checks.to_i.zero?
      return :all if up == checks

      up * 2 >= checks ? :most : :few
    end

    def uptime_segment_title(time, checks, up, title_format)
      label = time.in_time_zone.strftime(title_format)
      return "#{label} · no checks" if checks.to_i.zero?

      "#{label} · #{uptime_percent(100.0 * up / checks)} up · #{number_with_delimiter(checks)} #{'check'.pluralize(checks)}"
    end
end
