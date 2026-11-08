require "test_helper"
require_relative "apm_test_support"

class Apm::TransactionRegistryTest < ActiveSupport::TestCase
  include ApmFixtureClock

  include ApmTestSupport

  Entry = Struct.new(:kind, :name, :labels)

  setup do
    @project = projects(:storefront)
    @registry = Apm::TransactionRegistry.new(project_id: @project.id, environment: "production")
  end

  def entry(name, kind: "web") = Entry.new(kind, name, {})

  test "a client-sent (other) is admitted alongside new names that fit the cap" do
    ids = @registry.ids_for([ entry("Fresh#a"), entry(ApmTransaction::OTHER_NAME), entry("Fresh#b") ], totals: true)

    assert ids.values.all?(Integer), ids.inspect
    other = @project.apm_transactions.find_by!(environment: "production", kind: "web", name: ApmTransaction::OTHER_NAME)
    assert_equal other.id, ids[[ "web", ApmTransaction::OTHER_NAME ]]
    assert_not_equal other.id, ids[[ "web", "Fresh#a" ]]
  end

  test "a batch with new names and a client-sent (other) is processed" do
    process_batch(metrics_body([ metrics_transaction(name: "Fresh#a"), metrics_transaction(name: ApmTransaction::OTHER_NAME) ]))

    other = @project.apm_transactions.find_by!(environment: "production", kind: "web", name: ApmTransaction::OTHER_NAME)
    assert_equal 3, ApmMinuteStat.find_by!(apm_transaction_id: other.id).requests_count
  end

  test "an id that stays unresolved raises instead of mapping to nil" do
    @registry.define_singleton_method(:insert_missing) { |*| nil }
    error = assert_raises(Apm::TransactionRegistry::Unresolved) { @registry.ids_for([ entry("Fresh#a") ]) }
    assert_not_includes error.message, "Fresh#a"
  end

  test "new names are inserted in [kind, name] order, whatever the payload order" do
    sql = Apm::TransactionRegistry::InsertSql.new(project_id: @project.id, environment: "production", now: Time.current)
      .for([ [ "web", "Zed#z" ], [ "job", "B::Job" ], [ "web", "Alpha#a" ] ], {})
    positions = [ "'B::Job'", "'Alpha#a'", "'Zed#z'" ].map { sql.index(it) }
    assert_equal positions.sort, positions
  end

  test "stale rows are refreshed in id order under a row lock" do
    rows = [ apm_transactions(:checkout_create), apm_transactions(:products_show) ].sort_by(&:id)
    rows.each { it.update_columns(last_seen_at: 2.hours.ago) }
    statements = statements_in { @registry.ids_for(rows.reverse.map { entry(it.name) }) }

    update = statements.find { it.include?("FOR NO KEY UPDATE") }
    assert update, statements.join("\n")
    assert_operator update.index("CAST(#{rows.first.id} AS bigint)"), :<, update.index("CAST(#{rows.last.id} AS bigint)")
    rows.each { assert_in_delta Time.current, it.reload.last_seen_at, 5 }
  end
end
