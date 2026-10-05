# The issue list's summary strip for one project, period and (optional)
# environment: events with a sparkline and a delta against the previous period,
# new issues, regressions and users affected.
#
# The strip's numbers are cached for 30 seconds. Only integers are cached,
# never issue text or user identifiers.
class IssueSummary
  Period = Data.define(:key, :step, :buckets, :comparison) do
    def duration = step * buckets
  end

  PERIODS = {
    "1h" => Period.new(key: "1h", step: 1.hour, buckets: 1, comparison: "prev. hour"),
    "24h" => Period.new(key: "24h", step: 1.hour, buckets: 24, comparison: "prev. day"),
    "7d" => Period.new(key: "7d", step: 6.hours, buckets: 28, comparison: "prev. week"),
    "30d" => Period.new(key: "30d", step: 1.day, buckets: 30, comparison: "prev. 30 days")
  }.freeze
  DEFAULT_PERIOD = "24h".freeze
  SPARKLINE_MIN_POINTS = 12
  ENVIRONMENT = /\A[a-z0-9][a-z0-9_-]{0,31}\z/
  CACHE_TTL = 30.seconds

  attr_reader :project, :period, :environment

  def self.periods = PERIODS.values

  def initialize(project, period: nil, environment: nil)
    @project = project
    @period = PERIODS.fetch(period.to_s, PERIODS[DEFAULT_PERIOD])
    @environment = environment.to_s.match?(ENVIRONMENT) ? environment.to_s : nil
  end

  def events = numbers[:events]

  def sparkline = numbers[:sparkline]

  # Percentage change against the previous period; nil when that was zero.
  def events_change
    previous = numbers[:previous_events]
    ((events - previous) * 100.0 / previous).round unless previous.zero?
  end

  def new_issues = numbers[:new_issues]

  def new_last_hour = numbers[:new_last_hour]

  def regressions = numbers[:regressions]

  def users_affected = numbers[:users_affected]

  # Cached briefly and expired by triage, so triage shows up at once.
  def unresolved_count
    @unresolved_count ||= project.cached_unresolved_count(environment)
  end

  private
    def numbers
      @numbers ||= Rails.cache.fetch([ "summary", project.id, environment, period.key ], expires_in: CACHE_TTL) do
        event_numbers.merge(issue_numbers, users_affected: IssueUser.distinct_users(project, since:, environment:))
      end
    end

    def issues
      environment ? project.issues.in_environment(environment) : project.issues
    end

    def since = Time.current - period.duration

    # One query covering this period and the previous one.
    def event_numbers
      values = event_series
      {
        events: trailing_events(values, 0),
        previous_events: trailing_events(values, 1),
        sparkline: values.last([ period.buckets, SPARKLINE_MIN_POINTS ].max)
      }
    end

    # Events in the trailing period that ended `offset` periods ago, from
    # epoch-aligned buckets: the bucket holding the window's end (all of the
    # current one, so far), the whole buckets in between, and the elapsed
    # share of the bucket the window starts in. Without that share, "1h" would
    # count only the current clock hour, a few minutes early in the hour.
    def trailing_events(values, offset)
      last = values.size - 1 - (offset * period.buckets)
      head = offset.zero? ? values[last] : values[last] * elapsed
      middle = values[(last - period.buckets + 1)...last].sum
      (head + middle + (values[last - period.buckets] * (1 - elapsed))).round
    end

    def elapsed = @elapsed ||= TimeSeries.elapsed_fraction(period.step)

    def event_series
      buckets = [ (period.buckets * 2) + 1, SPARKLINE_MIN_POINTS ].max
      from = TimeSeries.window_start(period.step, buckets)
      ProjectHourlyCount.series(project, from:, buckets:, step: period.step, environment:)
    end

    def issue_numbers
      new_issues, new_last_hour, regressions = issues.pick(
        count_where("issues.first_seen_at >= ?", since),
        count_where("issues.first_seen_at >= ?", 1.hour.ago),
        count_where("issues.status = 'unresolved' AND issues.regressed_at IS NOT NULL")
      )
      { new_issues:, new_last_hour:, regressions: }
    end

    def count_where(condition, *binds)
      Arel.sql(Issue.sanitize_sql_array([ "COUNT(*) FILTER (WHERE #{condition})", *binds ]))
    end
end
