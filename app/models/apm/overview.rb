# The Performance overview of one app and environment (docs/ARCHITECTURE.md
# §13.8–13.9): the KPI tiles and the time-by-layer chart of the tab's total
# row, the tab counts, and the table of transactions sorted by time
# consumed. Read-only; a fixed number of statements however many
# transactions the app has. The per-transaction figures (numbers only, keyed
# by id) cover both tabs and are cached per range.cache_step.
#
#   overview = Apm::Overview.new(project, selection)
#   overview.tiles  # => [Tile(:rate, "Requests per minute", …), Tile(:average, …), …]
#   overview.rows   # => the first ROW_LIMIT rows unless "show all"
class Apm::Overview
  ROW_LIMIT = 25
  PERCENTILE_TILES = [ 75, 90, 95, 99 ].freeze
  LABELS = {
    "web" => { rate: "Requests per minute", failed: "Failed requests", noun: "request", nouns: "endpoints" },
    "job" => { rate: "Runs per minute", failed: "Failed runs", noun: "job", nouns: "jobs" }
  }.freeze
  SORT_VALUES = {
    "time" => :duration_ms.to_proc,
    "p95" => ->(figures) { figures.p95.to_f },
    "rate" => :count.to_proc,
    "failed" => :failed.to_proc
  }.freeze

  # format: :rate (per minute), :duration (ms) or :percent (a fraction);
  # change: the p95 tile's rise in % when the total is Slower.
  Tile = Data.define(:key, :label, :format, :value, :last_hour, :change)
  Row = Data.define(:transaction, :figures, :rate, :share, :slower_ratio, :sparkline, :n_plus_one) do
    def slower? = !slower_ratio.nil?
  end
  # One chart bin: the average split by layer (nil when empty) and the p95.
  Bin = Data.define(:time, :split, :average_ms, :p95)

  attr_reader :project, :selection

  delegate :range, :environment, :environments, :sort, :query, to: :selection

  def initialize(project, selection)
    @project = project
    @selection = selection
  end

  def any_data? = environment.present?

  # The tab in the URL, else web unless only jobs have sent data.
  def tab
    selection.requested_tab || (total_for("web").nil? && total_for("job") ? "jobs" : Apm::Selection::DEFAULT_TAB)
  end

  def kind = Apm::Selection::TABS.fetch(tab)

  def web? = kind == "web"

  def labels = LABELS.fetch(kind)

  def total = total_for(kind)

  def total_figures = figures_for(total)

  def data_in_range? = !total_figures.empty?

  # { "web" => 23, "jobs" => 14 }: transactions with data in the range.
  def tab_counts = Apm::Selection::TABS.transform_values { |kind| listed(kind).count { has_data?(it) } }

  def rows = @rows ||= build_rows(shown_transactions)

  def total_rows_count = ranked.size

  def limited? = !selection.all? && ranked.size > ROW_LIMIT

  def tiles
    last_hour = trend(:last_hour, total)
    [ rate_tile(last_hour), Tile.new(:average, "Average", :duration, total_figures.average_ms, last_hour.average_ms, nil),
      *PERCENTILE_TILES.map { percentile_tile(it, last_hour) }, failed_tile(last_hour) ]
  end

  def chart
    return [] unless total && data_in_range?

    stats.series(total.id).map do |time, distribution|
      Bin.new(time:, split: distribution.layer_split(:average), average_ms: distribution.average_ms, p95: distribution.percentile(95))
    end
  end

  # The selection's env and range plus this page's tab, sort and filter.
  def link_params(**overrides)
    current = { tab:, sort: (sort unless sort == Apm::StatsQuery::DEFAULT_SORT), q: query.presence }
    selection.link_params(**current.merge(overrides))
  end

  private
    def stats = @stats ||= Apm::StatsQuery.new(range)

    def transactions
      @transactions ||= environment ? project.apm_transactions.for_environment(environment).to_a : []
    end

    def total_for(kind) = transactions.find { it.total? && it.kind == kind }

    def listed(kind) = transactions.select { !it.total? && it.kind == kind }

    def figures
      @figures ||= Rails.cache.fetch(cache_key, expires_in: range.cache_step) { computed_figures }.transform_values { Apm::Figures.from_a(it) }
    end

    # { id => [numbers] } for every transaction of the environment, both
    # kinds, so the key leaves out the tab.
    def computed_figures = stats.by_transaction(transactions.map(&:id)).transform_values { Apm::Figures.from(it).to_a }

    def cache_key = [ "apm_overview", project.id, environment, *range.cache_key ]

    def figures_for(transaction) = (transaction && figures[transaction.id]) || Apm::Figures.empty

    def has_data?(transaction) = !figures_for(transaction).empty?

    def ranked
      @ranked ||= listed(kind).select { has_data?(it) && matches_query?(it) }
        .sort_by { [ -SORT_VALUES.fetch(sort).call(figures_for(it)), it.id ] }
    end

    def matches_query?(transaction)
      needle = query.downcase
      needle.empty? || [ transaction.name, transaction.route ].compact.any? { it.downcase.include?(needle) }
    end

    def shown_transactions = selection.all? ? ranked : ranked.first(ROW_LIMIT)

    # The shown rows and the total: their last-hour and past-day histograms
    # feed the Slower flags and the tiles' "Last hour" figures.
    def trend_ids = @trend_ids ||= (shown_transactions.map(&:id) + [ total&.id ]).compact

    def trend(window, transaction)
      return Apm::Distribution.empty if transaction.nil?

      stats.public_send(window, trend_ids).fetch(transaction.id) { Apm::Distribution.empty }
    end

    def slower_ratios = @slower_ratios ||= Apm::Slower.new(stats).ratios(trend_ids)

    def build_rows(transactions)
      ids = transactions.map(&:id)
      return [] if ids.empty?

      sparklines = stats.hourly_p95(ids)
      n_plus_one = ApmTrace.transaction_ids_with_n_plus_one(ids, since: range.start)
      transactions.map { build_row(it, sparklines.fetch(it.id), n_plus_one.include?(it.id)) }
    end

    def build_row(transaction, sparkline, n_plus_one)
      figures = figures_for(transaction)
      Row.new(transaction:, figures:, rate: figures.rate_per_minute(range.minutes), share: share_of(figures),
              slower_ratio: slower_ratios[transaction.id], sparkline:, n_plus_one:)
    end

    def share_of(figures)
      whole = total_figures.duration_ms.positive? ? total_figures.duration_ms : ranked.sum { figures_for(it).duration_ms }
      whole.positive? ? (figures.duration_ms / whole).clamp(0.0, 1.0) : 0.0
    end

    def rate_tile(last_hour)
      value = total_figures.empty? ? nil : total_figures.rate_per_minute(range.minutes)
      Tile.new(:rate, labels[:rate], :rate, value, (last_hour.count / last_hour_minutes unless last_hour.empty?), nil)
    end

    def percentile_tile(p, last_hour)
      change = p == 95 ? p95_change(last_hour) : nil
      Tile.new(:"p#{p}", "p#{p}", :duration, total_figures.percentile(p), last_hour.percentile(p), change)
    end

    def failed_tile(last_hour)
      Tile.new(:failed, labels[:failed], :percent, total_figures.failed_rate, last_hour.failed_rate, nil)
    end

    # The rise of the last hour's p95 over the past day's, in whole percent,
    # when the total is Slower; else nil.
    def p95_change(last_hour)
      ratio = Apm::Slower.ratio(last_hour, trend(:past_day, total))
      ((ratio - 1) * 100).round if ratio
    end

    def last_hour_minutes = (range.now - range.last_hour_start) / 60.0
end
