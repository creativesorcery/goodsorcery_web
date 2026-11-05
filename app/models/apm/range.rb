# A time range of the Performance pages (docs/ARCHITECTURE.md §13.6): which
# rows its figures and chart read, where it starts and how its chart is
# binned. Bins are epoch-aligned (TimeSeries.align). The start is clamped to
# the account's retention, so a downgrade applies at query time.
#
#   range = Apm::Range.pick(params[:range], entitlements: account.entitlements)
#   range.start      # first minute/hour the figures read
#   range.bin_times  # chart bin starts, oldest first
class Apm::Range
  Spec = Data.define(:days, :span, :figure_rows, :chart_rows, :bin, :bins, :label)

  SPECS = {
    "15m" => Spec.new(days: 1, span: 15.minutes, figure_rows: :minute, chart_rows: :minute, bin: 1.minute, bins: 15,
                      label: "last 15 minutes"),
    "1h" => Spec.new(days: 1, span: 1.hour, figure_rows: :minute, chart_rows: :minute, bin: 1.minute, bins: 60,
                     label: "last hour"),
    "1d" => Spec.new(days: 1, span: 24.hours, figure_rows: :hour, chart_rows: :minute, bin: 15.minutes, bins: 96,
                     label: "last 24 hours"),
    "7d" => Spec.new(days: 7, span: 168.hours, figure_rows: :hour, chart_rows: :hour, bin: 2.hours, bins: 84,
                     label: "last 7 days"),
    "30d" => Spec.new(days: 30, span: 720.hours, figure_rows: :hour, chart_rows: :hour, bin: 8.hours, bins: 90,
                      label: "last 30 days")
  }.freeze
  KEYS = SPECS.keys.freeze
  DEFAULT = "1d".freeze

  # The range for a URL param: unknown keys and ranges the account may not
  # see (a crafted URL, or after a downgrade) fall back to DEFAULT.
  def self.pick(key, entitlements:, now: Time.current)
    retention_days = entitlements.apm_retention_days
    range = new(KEYS.include?(key) ? key : DEFAULT, now:, retention_days:)
    range.locked?(entitlements) ? new(DEFAULT, now:, retention_days:) : range
  end

  attr_reader :key, :now, :retention_days

  delegate :days, :span, :figure_rows, :chart_rows, :bin, :bins, :label, to: :@spec

  def initialize(key = DEFAULT, now: Time.current, retention_days: Entitlements::MAX_APM_RETENTION_DAYS)
    @key = KEYS.include?(key) ? key : DEFAULT
    @spec = SPECS.fetch(@key)
    @now = now
    @retention_days = retention_days
  end

  def locked?(entitlements) = !entitlements.allows_apm_range?(days)

  # The first minute (15m, 1h) or hour (longer ranges) of the figures.
  def start = [ unclamped_start, retention_cutoff ].max

  def retention_cutoff = now - retention_days.days

  def bin_start = TimeSeries.window_start(bin, bins, now:)

  def bin_times = Array.new(bins) { |index| bin_start + (index * bin) }

  # Elapsed minutes from the start to now, for per-minute rates.
  def minutes = [ (now - start) / 60.0, 1.0 ].max

  def last_hour_start = floor_minute - 59.minutes

  def past_day_start = floor_hour - 23.hours

  def cache_key = [ key, floor_minute.to_i ]

  private
    def floor_minute = TimeSeries.align(now, 1.minute)

    def floor_hour = TimeSeries.align(now, 1.hour)

    def unclamped_start
      floor = figure_rows == :minute ? floor_minute : floor_hour
      floor - span + (figure_rows == :minute ? 1.minute : 1.hour)
    end
end
