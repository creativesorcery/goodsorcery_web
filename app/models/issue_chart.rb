# The issue page's occurrences chart: bucketed counts for 24h (hourly),
# 7d (6-hourly) or 30d (daily), plus bar titles and five axis labels.
#
# Only numbers are cached (5 min, 7d/30d only; 24h stays fresh for live
# reloads). Labels are formatted per request in the viewer's time zone.
class IssueChart
  PERIODS = IssueHourlyCount::PERIODS.keys.freeze
  DEFAULT_PERIOD = "24h".freeze
  CACHE_TTL = 5.minutes
  AXIS_TICKS = 4
  TICK_FORMATS = { "24h" => "%H:%M", "7d" => "%a %-d", "30d" => "%b %-d" }.freeze
  TITLE_FORMATS = { "24h" => "%b %-d %H:%M", "7d" => "%b %-d %H:%M", "30d" => "%b %-d" }.freeze

  attr_reader :issue, :period

  def initialize(issue, period = nil)
    @issue = issue
    @period = PERIODS.include?(period.to_s) ? period.to_s : DEFAULT_PERIOD
  end

  def points
    @points ||= cached? ? Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { series } : series
  end

  def values = points.map(&:last)

  def total = values.sum

  # "Oct 4 09:00 · 12 events", one per bar.
  def titles
    points.map { |time, count| "#{time.in_time_zone.strftime(TITLE_FORMATS[period])} · #{count} #{'event'.pluralize(count)}" }
  end

  # Five labels spread across the chart; the last always reads "now".
  def axis_labels
    ticks = Array.new(AXIS_TICKS) { |index| points[(points.size * index) / AXIS_TICKS].first }
    ticks.map { |time| tick_label(time) } << "now"
  end

  def cache_key = [ "issue_chart", issue.id, period ]

  private
    def cached? = period != DEFAULT_PERIOD

    def series = IssueHourlyCount.series(issue, period)

    def tick_label(time)
      local = time.in_time_zone
      label = local.strftime(TICK_FORMATS[period])
      period == DEFAULT_PERIOD && local.to_date != Time.zone.today ? "#{label} yesterday" : label
    end
end
