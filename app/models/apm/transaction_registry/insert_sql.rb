# The registry's single INSERT for missing transactions. Each new name of a
# kind gets a rank (1, 2, …) and is admitted while
# rank <= Apm::MAX_TRANSACTIONS − the names that kind already has (its
# "room"). The total rows get rank 0 and are always admitted. The (other)
# row gets −(the kind's new names) and is admitted only when they don't all
# fit, so it exists only once something is folded into it. Conflicts with
# rows inserted concurrently are skipped (ON CONFLICT DO NOTHING) and
# re-selected by the registry. Every value is quoted by sanitize_sql_array;
# the quoted VALUES rows are spliced in after the statement's own binds are
# filled, so a ":" or "?" inside a name or route is never read as a bind.
class Apm::TransactionRegistry::InsertSql
  COLUMNS = %w[kind name total http_method route adapter queue source_file rank].freeze
  ROW = "(?, ?, CAST(? AS boolean), ?, ?, ?, ?, ?, CAST(? AS integer))".freeze
  VALUES_TOKEN = "/*values*/".freeze
  SQL = <<~SQL.squish.freeze
    INSERT INTO apm_transactions (project_id, environment, kind, name, total, http_method, route, adapter, queue,
      source_file, first_seen_at, last_seen_at, created_at, updated_at)
    SELECT CAST(:project_id AS bigint), CAST(:environment AS varchar), v.kind, v.name, v.total, v.http_method, v.route,
      v.adapter, v.queue, v.source_file, CAST(:now AS timestamp), CAST(:now AS timestamp), CAST(:now AS timestamp),
      CAST(:now AS timestamp)
    FROM (VALUES #{VALUES_TOKEN}) AS v(#{COLUMNS.join(", ")})
    CROSS JOIN LATERAL (
      SELECT CAST(:max AS integer) - COUNT(*) AS room FROM apm_transactions t
      WHERE t.project_id = CAST(:project_id AS bigint) AND t.environment = CAST(:environment AS varchar)
        AND t.kind = v.kind AND NOT t.total AND t.name <> CAST(:other AS varchar)) existing
    WHERE v.rank = 0 OR (v.rank > 0 AND v.rank <= existing.room) OR (v.rank < 0 AND -v.rank > existing.room)
    ON CONFLICT (project_id, environment, kind, name) DO NOTHING
    RETURNING kind, name, id
  SQL

  def initialize(project_id:, environment:, now:)
    @project_id = project_id
    @environment = environment
    @now = now
  end

  # The statement; it returns rows of [kind, name, id] when run.
  def for(keys, labels)
    binds = { project_id: @project_id, environment: @environment, now: @now, max: Apm::MAX_TRANSACTIONS,
              other: ApmTransaction::OTHER_NAME }
    ApmTransaction.sanitize_sql_array([ SQL, binds ]).sub(VALUES_TOKEN) { values(keys, labels) }
  end

  private
    def values(keys, labels)
      ranks = ranks_for(keys)
      keys.map do |kind, name|
        label = special?(kind, name) ? {} : labels.fetch([ kind, name ], {})
        ApmTransaction.sanitize_sql_array([ ROW, kind, name, total?(kind, name), *Apm::TransactionRegistry::LABELS.map { label[it] },
                                            ranks[[ kind, name ]] ])
      end.join(", ")
    end

    # New names 1, 2, … per kind; totals 0; (other) −(the kind's new names).
    def ranks_for(keys)
      named = keys.reject { special?(*it) }.group_by(&:first)
      ranks = named.values.flat_map { |list| list.each_with_index.map { |key, index| [ key, index + 1 ] } }.to_h
      keys.each { |kind, name| ranks[[ kind, name ]] ||= total?(kind, name) ? 0 : -named.fetch(kind, []).size }
      ranks
    end

    def special?(kind, name) = name == ApmTransaction::OTHER_NAME || total?(kind, name)

    def total?(kind, name) = ApmTransaction::TOTAL_NAMES[kind] == name
end
