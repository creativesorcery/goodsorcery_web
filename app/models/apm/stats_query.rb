# Reads merged histograms for the Performance pages (docs/ARCHITECTURE.md
# §13.6). Every method costs one or two grouped statements, however many
# transactions it is asked about: one sums the bucket arrays element-wise
# (unnest … WITH ORDINALITY), the other the scalar columns. Results are
# memoized per instance, so a page may ask twice for free.
#
#   stats = Apm::StatsQuery.new(range)
#   stats.by_transaction(ids)        # => { id => Apm::Distribution } over the range
#   stats.last_hour(ids)             # => { id => Apm::Distribution } (minute rows, last 60 minutes)
#   stats.past_day(ids)              # => { id => Apm::Distribution } (hourly rows, last 24 hours)
#   stats.series(id)                 # => [[bin_start, Apm::Distribution], …] zero-filled
#   stats.hourly_p95(ids, hours: 24) # => { id => [Float | nil] * hours }, oldest first
#   stats.ranked(ids, sort: "time")  # => ids with data in the range, largest first
#
# Ids without data are absent from the hashes (fetch with a default of
# Apm::Distribution.empty).
class Apm::StatsQuery
  UNNEST = "CROSS JOIN LATERAL unnest(bucket_counts, bucket_db_ms, bucket_http_ms, bucket_view_ms, bucket_ruby_ms, " \
           "queue_wait_counts) WITH ORDINALITY AS b(c, db, http, view, app, qw, i)".freeze
  BUCKET_SUMS = [ "b.i", "SUM(b.c)", "SUM(b.db)", "SUM(b.http)", "SUM(b.view)", "SUM(b.app)", "SUM(b.qw)" ].freeze
  SCALAR_SUMS = [ "SUM(requests_count)", "SUM(failed_count)", "SUM(duration_ms_sum)", "SUM(queue_wait_ms_sum)" ].freeze

  # The overview table's sorts, largest first: time consumed (the summed
  # duration), p95, request count, failed count.
  SORTS = {
    "time" => :duration_ms.to_proc,
    "p95" => ->(distribution) { distribution.percentile(95).to_f },
    "rate" => :count.to_proc,
    "failed" => :failed.to_proc
  }.freeze
  DEFAULT_SORT = "time".freeze

  attr_reader :range

  def initialize(range)
    @range = range
    @memo = {}
  end

  def by_transaction(ids)
    memoized(:by_transaction, ids) { distributions(stats_model(range.figure_rows), ids, from: range.start) }
  end

  def last_hour(ids)
    memoized(:last_hour, ids) { distributions(ApmMinuteStat, ids, from: range.last_hour_start) }
  end

  def past_day(ids)
    memoized(:past_day, ids) { distributions(ApmHourlyStat, ids, from: range.past_day_start) }
  end

  def series(id)
    memoized(:series, [ id ]) do
      binned = distributions(stats_model(range.chart_rows), [ id ], from: range.bin_start, bin: range.bin)
      range.bin_times.map { |time| [ time, binned.fetch([ id, time.to_i ]) { Apm::Distribution.empty } ] }
    end
  end

  def hourly_p95(ids, hours: 24)
    memoized(:hourly_p95, ids + [ hours ]) do
      from = TimeSeries.window_start(1.hour, hours, now: range.now)
      by_hour = bucket_rows(scoped(ApmHourlyStat, ids, from), [ :apm_transaction_id, bin_sql(ApmHourlyStat, 1.hour) ])
      ids.index_with { |id| hourly_values(by_hour, id, from, hours) }
    end
  end

  # The ids that have data in the range, sorted by SORTS[sort] descending
  # (ties by id). Unknown sorts use DEFAULT_SORT. Reuses #by_transaction.
  def ranked(ids, sort: DEFAULT_SORT)
    key = SORTS.fetch(sort.to_s) { SORTS.fetch(DEFAULT_SORT) }
    by_transaction(ids).sort_by { |id, distribution| [ -key.call(distribution), id ] }.map(&:first)
  end

  private
    def memoized(name, ids, &block) = @memo.fetch([ name, ids.sort ]) { @memo[[ name, ids.sort ]] = block.call }

    def stats_model(rows) = rows == :minute ? ApmMinuteStat : ApmHourlyStat

    def scoped(model, ids, from) = model.where(apm_transaction_id: ids).where(model.time_column => from..)

    # { id => Distribution }, or { [id, bin epoch] => Distribution } when binned.
    def distributions(model, ids, from:, bin: nil)
      return {} if ids.empty?

      keys = [ :apm_transaction_id, *(bin_sql(model, bin) if bin) ]
      scope = scoped(model, ids, from)
      buckets = bucket_rows(scope, keys)
      scalar_rows(scope, keys).to_h { |key, scalars| [ key, build(scalars, buckets.fetch(key, {})) ] }
    end

    def bin_sql(model, step)
      Arel.sql(format("date_bin('%d seconds', %s, TIMESTAMP '1970-01-01')", step.to_i, model.time_column))
    end

    # { key => { bucket index => [count, db, http, view, app, queue wait count] } }
    def bucket_rows(scope, keys)
      rows = scope.from("#{scope.quoted_table_name} #{UNNEST}").where("b.c > 0 OR b.qw > 0")
        .group(*keys, "b.i").pluck(*keys, *BUCKET_SUMS.map { Arel.sql(it) })
      rows.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |row, result|
        key, (index, *sums) = split_key(row, keys.size)
        result[key][index - 1] = sums
      end
    end

    def scalar_rows(scope, keys)
      scope.group(*keys).pluck(*keys, *SCALAR_SUMS.map { Arel.sql(it) }).map { split_key(it, keys.size) }
    end

    def split_key(row, size)
      key = size == 1 ? row.first : [ row.first, row.second.to_i ]
      [ key, row.drop(size) ]
    end

    def build((count, failed, duration_ms, queue_wait_ms), buckets)
      arrays = Apm::Distribution::ARRAYS.to_h { [ it, Apm::Histogram.zeros ] }
      buckets.each { |index, sums| Apm::Distribution::ARRAYS.zip(sums) { |name, value| arrays[name][index] = value } }
      Apm::Distribution.new(count:, failed:, duration_ms:, queue_wait_ms:, **arrays)
    end

    def hourly_values(by_hour, id, from, hours)
      Array.new(hours) do |index|
        buckets = by_hour.fetch([ id, (from + index.hours).to_i ], nil)
        buckets && build([ buckets.values.sum(&:first), 0, 0, 0 ], buckets).percentile(95)
      end
    end
end
