# The Uptime page's list (docs/ARCHITECTURE.md §12.8): each monitor with its
# uptime percentages and 24-hour status bar. A fixed 3 queries however many
# monitors there are: the monitors, the percentages and the hourly bars.
#
#   UptimeOverview.new(project.uptime_monitors.order(:name)).rows.each { |row| row.monitor ... }
class UptimeOverview
  BAR_HOURS = 24

  Row = Data.define(:monitor, :percentages, :bars)

  def initialize(monitors, now: Time.current)
    @monitors = monitors
    @now = now
  end

  def rows
    @rows ||= build_rows(@monitors.to_a)
  end

  def empty? = rows.empty?

  def size = rows.size

  private
    def build_rows(monitors)
      return [] if monitors.empty?

      ids = monitors.map(&:id)
      percentages = UptimeHourlyCount.uptime_percentages(ids, now: @now)
      bars = UptimeHourlyCount.hourly_bars(ids, hours: BAR_HOURS, now: @now)
      monitors.map { |monitor| Row.new(monitor:, percentages: percentages.fetch(monitor.id), bars: bars.fetch(monitor.id)) }
    end
end
