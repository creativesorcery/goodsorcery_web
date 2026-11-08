require "test_helper"
require Rails.root.join("db/migrate/20261107000001_move_monthly_event_quota_to_entitlements")

# Runs the migration both ways inside the test transaction (Postgres DDL is
# transactional, so the rollback restores the schema). Reads and writes go
# through raw SQL, never the Account model, whose column list must not change.
class MoveMonthlyEventQuotaToEntitlementsTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @acme, @umbrella = accounts(:acme).id, accounts(:umbrella).id
    @fresh = Account.create!(name: "Fresh").id
  end

  test "down restores the column, copies stored quotas back and removes the key" do
    store(@acme, { "monthly_event_quota" => 500, "max_monitors" => 2 })
    store(@umbrella, { "monthly_event_quota" => nil })

    migrate(:down)

    assert_equal [ 500, { "max_monitors" => 2 } ], row(@acme)
    assert_equal [ nil, {} ], row(@umbrella), "a stored null is no quota"
    assert_equal [ nil, {} ], row(@fresh)
  end

  test "up copies each non-null quota unless the key is already stored, then drops the column" do
    migrate(:down)
    write(@acme, quota: 700, values: { "max_projects" => 5 })
    write(@umbrella, quota: 800, values: { "monthly_event_quota" => 1_234 })
    write(@fresh, quota: nil, values: {})

    migrate(:up)

    assert_not connection.column_exists?(:accounts, :monthly_event_quota)
    assert_equal({ "max_projects" => 5, "monthly_event_quota" => 700 }, values(@acme))
    assert_equal({ "monthly_event_quota" => 1_234 }, values(@umbrella), "a stored value wins")
    assert_equal({}, values(@fresh), "no quota copies nothing")
  end

  test "a round trip keeps a quota" do
    store(@acme, { "monthly_event_quota" => 42_000 })

    migrate(:down)
    migrate(:up)

    assert_equal({ "monthly_event_quota" => 42_000 }, values(@acme))
  end

  private
    def connection = ActiveRecord::Base.connection

    def migrate(direction)
      ActiveRecord::Migration.suppress_messages { MoveMonthlyEventQuotaToEntitlements.new.migrate(direction) }
    end

    def store(id, values)
      connection.exec_update("UPDATE accounts SET entitlement_values = #{connection.quote(values.to_json)}::jsonb WHERE id = #{Integer(id)}")
    end

    def write(id, quota:, values:)
      store(id, values)
      connection.exec_update("UPDATE accounts SET monthly_event_quota = #{connection.quote(quota)} WHERE id = #{Integer(id)}")
    end

    def row(id)
      quota, values = connection.select_rows("SELECT monthly_event_quota, entitlement_values FROM accounts WHERE id = #{Integer(id)}").first
      [ quota&.to_i, JSON.parse(values) ]
    end

    def values(id)
      JSON.parse(connection.select_value("SELECT entitlement_values FROM accounts WHERE id = #{Integer(id)}"))
    end
end
