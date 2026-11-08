# Adds a metrics batch to the minute and hourly rows (docs/ARCHITECTURE.md
# §13.4). Entries are merged in Ruby first per [transaction id, minute]
# (several names can fold into (other), and one upsert cannot update a row
# twice), plus one entry per minute for the kind's total row. Then two
# multi-row upserts that add every column element-wise, rows sorted by
# [transaction id, time] and always minutes before hours: a fixed lock
# order, so concurrent batches never deadlock. The minute → hour rollup
# happens here, at write time; a late minute lands in both tables. The
# bucket_ruby_ms columns hold the app-code layer (named before the protocol
# went language-neutral).
class Apm::StatsUpsert
  SCALARS = { requests_count: :count, failed_count: :failed, duration_ms_sum: :duration_ms, queue_wait_ms_sum: :queue_wait_ms }.freeze
  ARRAYS = { bucket_counts: :counts, bucket_db_ms: :db_ms, bucket_http_ms: :http_ms, bucket_view_ms: :view_ms,
             bucket_ruby_ms: :app_ms, queue_wait_counts: :queue_wait_counts }.freeze

  # The ON CONFLICT … DO UPDATE assignments: every column added.
  def self.add_sql(table)
    scalars = SCALARS.keys.map { "#{it} = #{table}.#{it} + EXCLUDED.#{it}" }
    arrays = ARRAYS.keys.map do |column|
      "#{column} = ARRAY(SELECT a + b FROM unnest(#{table}.#{column}, EXCLUDED.#{column}) WITH ORDINALITY AS t(a, b, i) ORDER BY i)"
    end
    Arel.sql((scalars + arrays).join(", "))
  end

  # One minute or hourly row's attributes for a Distribution.
  def self.row(id, time_column, time, distribution)
    { apm_transaction_id: id, time_column => time,
      **SCALARS.transform_values { distribution.public_send(it) }, **ARRAYS.transform_values { distribution.public_send(it) } }
  end

  MINUTE_ADD_SQL = add_sql("apm_minute_stats")
  HOUR_ADD_SQL = add_sql("apm_hourly_stats")

  # ids: { [kind, name] => transaction id }; total_ids: { kind => total row id }.
  def initialize(ids:, total_ids:)
    @ids = ids
    @total_ids = total_ids
  end

  def upsert(entries)
    by_minute = merged(entries)
    return if by_minute.empty?

    ApmMinuteStat.upsert_all(rows(by_minute, :minute), on_duplicate: MINUTE_ADD_SQL, record_timestamps: false)
    ApmHourlyStat.upsert_all(rows(by_hour(by_minute), :hour), on_duplicate: HOUR_ADD_SQL, record_timestamps: false)
  end

  private
    # { [transaction id, minute] => Distribution }
    def merged(entries)
      entries.each_with_object(Hash.new { Apm::Distribution.empty }) do |entry, sums|
        [ @ids[[ entry.kind, entry.name ]], @total_ids[entry.kind] ].each do |id|
          sums[[ id, entry.minute ]] += entry.distribution
        end
      end
    end

    def by_hour(by_minute)
      by_minute.each_with_object(Hash.new { Apm::Distribution.empty }) do |((id, minute), distribution), sums|
        sums[[ id, TimeSeries.align(minute, 1.hour) ]] += distribution
      end
    end

    def rows(sums, time_column)
      sums.sort_by { |(id, time), _| [ id, time ] }.map { |(id, time), distribution| self.class.row(id, time_column, time, distribution) }
    end
end
