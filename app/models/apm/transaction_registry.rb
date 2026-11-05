# Maps a batch's (kind, name) pairs to apm_transactions ids for one app and
# environment (docs/ARCHITECTURE.md §13.4), in at most four statements:
#
# 1. one SELECT of the names (and the total and (other) rows);
# 2. one INSERT … SELECT … ON CONFLICT DO NOTHING RETURNING of the missing
#    ones, which admits new names only while the app has fewer than
#    Apm::MAX_TRANSACTIONS of that kind (the (other) and total rows are
#    always admitted and never counted);
# 3. one re-SELECT of names that conflicted with a concurrent insert, or
#    were refused by the cap (those map to (other));
# 4. one UPDATE of last_seen_at and the latest labels for rows not seen for
#    an hour, so hot rows are not rewritten every minute.
#
# Inserts and updates take their locks in [kind, name] and id order, so
# batches flushed at the same moment by many processes don't deadlock.
#
# The cap is soft under concurrency (two batches may each add the last
# names); that is accepted. Run it inside the batch transaction, uncached.
class Apm::TransactionRegistry
  class Unresolved < StandardError; end

  LABELS = %i[http_method route adapter queue source_file].freeze
  REFRESH_AFTER = 1.hour
  VALUES_TOKEN = "/*values*/".freeze
  REFRESH_SQL = <<~SQL.squish.freeze
    WITH locked AS MATERIALIZED (
      SELECT id FROM apm_transactions WHERE id IN (:ids) AND last_seen_at < CAST(:cutoff AS timestamp)
      ORDER BY id FOR NO KEY UPDATE)
    UPDATE apm_transactions SET last_seen_at = CAST(:now AS timestamp), updated_at = CAST(:now AS timestamp),
      #{LABELS.map { "#{it} = COALESCE(v.#{it}, apm_transactions.#{it})" }.join(", ")}
    FROM (VALUES #{VALUES_TOKEN}) AS v(id, #{LABELS.join(", ")})
    WHERE apm_transactions.id = v.id AND apm_transactions.id IN (SELECT id FROM locked)
  SQL

  def initialize(project_id:, environment:, now: Time.current)
    @project_id = project_id
    @environment = environment
    @now = now
    @rows = {}
  end

  # { [kind, name] => id } for every entry (names past the cap map to the
  # (other) id). With totals: true the kinds' total rows are ensured too.
  # Raises Unresolved rather than hand back a nil id.
  def ids_for(entries, totals: false)
    labels = latest_labels(entries)
    resolve(labels.keys, labels, totals:)
    labels.keys.index_with { resolved_id(it) }
  end

  # The id of a kind's total row (after ids_for with totals: true).
  def total_id(kind) = id_of([ kind, ApmTransaction::TOTAL_NAMES.fetch(kind) ])

  private
    def id_of(key) = @rows[key]&.first

    def resolved_id(key)
      id_of(key) || id_of(other_key(key.first)) || raise(Unresolved, "no transaction row for a #{key.first} name")
    end

    def other_key(kind) = [ kind, ApmTransaction::OTHER_NAME ]

    def total_key(kind) = [ kind, ApmTransaction::TOTAL_NAMES.fetch(kind) ]

    def latest_labels(entries)
      entries.sort_by { it.respond_to?(:minute) ? it.minute.to_i : 0 }.to_h { [ [ it.kind, it.name ], it.labels ] }
    end

    def resolve(keys, labels, totals:)
      kinds = keys.map(&:first).uniq
      special = kinds.map { other_key(it) } + (totals ? kinds.map { total_key(it) } : [])
      @rows.merge!(select_rows(keys + special))
      insert_missing(keys, special, labels)
      refresh(labels)
    end

    # (other) rows are offered only for kinds with new names (InsertSql admits
    # them only when those names overflow the cap).
    def insert_missing(keys, special, labels)
      missing = keys.reject { @rows.key?(it) }
      kinds = missing.map(&:first)
      offered = special.select { total?(it) || kinds.include?(it.first) }.reject { @rows.key?(it) }
      inserts = missing + offered
      return if inserts.empty?

      @rows.merge!(insert_rows(inserts, labels, admitted: keys.select { other?(it) }))
      unresolved = inserts.reject { @rows.key?(it) }
      @rows.merge!(select_rows(unresolved)) if unresolved.any?
    end

    def total?(key) = key.last == ApmTransaction::TOTAL_NAMES[key.first]

    def other?(key) = key.last == ApmTransaction::OTHER_NAME

    # { key => [id, last_seen_at] }
    def select_rows(keys)
      wanted = keys.to_set
      ApmTransaction.where(project_id: @project_id, environment: @environment, kind: keys.map(&:first).uniq, name: keys.map(&:last).uniq)
        .pluck(:kind, :name, :id, :last_seen_at).each_with_object({}) do |(kind, name, id, seen), rows|
          rows[[ kind, name ]] = [ id, seen ] if wanted.include?([ kind, name ])
        end
    end

    # A client-sent (other) is always admitted (see InsertSql).
    def insert_rows(keys, labels, admitted:)
      sql = Apm::TransactionRegistry::InsertSql.new(project_id: @project_id, environment: @environment, now: @now)
      ApmTransaction.connection.select_rows(sql.for(keys, labels, admitted:)).to_h { |kind, name, id| [ [ kind, name ], [ id, @now ] ] }
    end

    def refresh(labels)
      stale = @rows.select { |_, (_, seen)| seen < @now - REFRESH_AFTER }.values.map(&:first).sort
      return if stale.empty?

      by_id = labels.filter_map { |key, values| [ id_of(key), values ] if id_of(key) }.to_h
      ApmTransaction.connection.update(refresh_sql(stale, by_id))
    end

    # The quoted VALUES rows are spliced in after the binds are filled (see InsertSql).
    def refresh_sql(ids, labels_by_id)
      values = ids.map do |id|
        ApmTransaction.sanitize_sql_array([ "(CAST(? AS bigint), ?, ?, ?, ?, ?)", id, *LABELS.map { labels_by_id.fetch(id, {})[it] } ])
      end
      ApmTransaction.sanitize_sql_array([ REFRESH_SQL, { now: @now, cutoff: @now - REFRESH_AFTER, ids: } ])
        .sub(VALUES_TOKEN) { values.join(", ") }
    end
end
