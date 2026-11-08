# The endpoint (or job) page of one transaction (docs/ARCHITECTURE.md
# §13.8–13.9): the stat ribbon, the five-line response-time chart, the
# "Where time goes" bars and sentence, the Slower line, the unresolved
# issues raised by this transaction and its slow traces. Read-only; a fixed
# number of statements.
#
#   report = Apm::EndpointReport.new(transaction, selection)
#   report.ribbon  # => [Stat(:requests, …), Stat(:average, …), …, Stat(:failed, …)]
#   report.bars    # => [Bar(:average, "Average", 340.0, { db:, http:, view:, app: }), Bar(75, "p75", …), …]
class Apm::EndpointReport
  PERCENTILES = [ 75, 90, 95, 99 ].freeze
  LINES = [ :average, *PERCENTILES ].freeze
  ISSUE_LIMIT = 5
  CLIMB_HOURS = 6
  CLIMB_RATIO = 1.25

  # change: the p95's Slower ratio (only on the p95 stat).
  Stat = Data.define(:key, :label, :value, :last_hour, :change)
  Bar = Data.define(:key, :label, :value, :split)
  Series = Data.define(:times, :lines)

  attr_reader :transaction, :selection

  delegate :range, to: :selection

  def initialize(transaction, selection)
    @transaction = transaction
    @selection = selection
  end

  def distribution = @distribution ||= window(:by_transaction)

  def last_hour = @last_hour ||= window(:last_hour)

  def past_day = @past_day ||= window(:past_day)

  def empty? = distribution.empty?

  def rate_per_minute = distribution.rate_per_minute(range.minutes)

  def last_hour_rate = last_hour.empty? ? nil : last_hour.count / last_hour_minutes

  def ribbon
    [ Stat.new(:requests, nil, distribution.count, last_hour_rate, nil),
      Stat.new(:average, "Average", distribution.average_ms, last_hour.average_ms, nil),
      *PERCENTILES.map { Stat.new(:"p#{it}", "p#{it}", distribution.percentile(it), last_hour.percentile(it), (slower_ratio if it == 95)) },
      Stat.new(:failed, "Failed", distribution.failed_rate, last_hour.failed_rate, nil) ]
  end

  # Five lines over the range's bins; nil where a bin has no requests.
  def series
    bins = stats.series(transaction.id)
    lines = LINES.index_with { |line| bins.map { |_, distribution| line_value(distribution, line) } }
    Series.new(times: bins.map(&:first), lines:)
  end

  def bars
    LINES.filter_map do |key|
      split = distribution.layer_split(key)
      split && Bar.new(key:, label: key == :average ? "Average" : "p#{key}", value: split.values.sum, split:)
    end
  end

  def summary_sentence = Apm::LayerSentence.new(bars, noun: transaction.web? ? "requests" : "runs").sentence

  # The last hour's p95 over the past day's when Slower, else nil.
  def slower_ratio
    return @slower_ratio if defined?(@slower_ratio)

    @slower_ratio = Apm::Slower.ratio(last_hour, past_day)
  end

  # When Slower: the start of the earliest of the last CLIMB_HOURS hours
  # from which every hourly p95 is at least CLIMB_RATIO times the day's.
  def climbing_since
    return unless slower_ratio && past_day.percentile(95)

    floor = CLIMB_RATIO * past_day.percentile(95)
    values = stats.hourly_p95([ transaction.id ], hours: CLIMB_HOURS).fetch(transaction.id)
    index = values.each_index.find { |i| values[i..].all? { it && it >= floor } }
    index && TimeSeries.window_start(1.hour, CLIMB_HOURS, now: range.now) + index.hours
  end

  # Unresolved issues of the app raised by this transaction in its
  # environment, most recently seen first.
  def issues = @issues ||= issue_scope.order(last_seen_at: :desc, id: :desc).limit(ISSUE_LIMIT).to_a

  def issues_count = @issues_count ||= issues.size < ISSUE_LIMIT ? issues.size : issue_scope.count

  def traces
    @traces ||= Apm::TraceList.new(transaction, range, sort: selection.trace_sort, page: selection.page)
  end

  private
    def stats = @stats ||= Apm::StatsQuery.new(range)

    def window(name) = stats.public_send(name, [ transaction.id ]).fetch(transaction.id) { Apm::Distribution.empty }

    def line_value(distribution, line) = line == :average ? distribution.average_ms : distribution.percentile(line)

    def last_hour_minutes = (range.now - range.last_hour_start) / 60.0

    def issue_scope
      transaction.project.issues.unresolved.in_environment(transaction.environment).where(transaction_name: transaction.name)
    end
end
