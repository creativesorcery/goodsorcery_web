require "test_helper"
require Rails.root.join("db/migrate/20261107000001_move_monthly_event_quota_to_entitlements")

# Runs the migration both ways inside the test transaction. Reads and writes
# go through raw SQL, never the Account model, which ignores the column.
class MoveMonthlyEventQuotaToEntitlementsTest < ActiveSupport::TestCase
  setup do
    @acme, @umbrella = accounts(:acme).id, accounts(:umbrella).id
    @fresh = Account.create!(name: "Fresh").id
  end

  test "up copies each non-null quota unless the key is already stored, and keeps the column" do
    write(@acme, quota: 700, values: { "max_projects" => 5 })
    write(@umbrella, quota: 800, values: { "monthly_event_quota" => 1_234 })
    write(@fresh, quota: nil, values: {})

    migrate(:up)

    assert connection.column_exists?(:accounts, :monthly_event_quota), "the previous release still reads it"
    assert_equal [ 700, { "max_projects" => 5, "monthly_event_quota" => 700 } ], row(@acme)
    assert_equal [ 800, { "monthly_event_quota" => 1_234 } ], row(@umbrella), "a stored value wins"
    assert_equal [ nil, {} ], row(@fresh), "no quota copies nothing"
  end

  test "down copies stored quotas back into the column and removes the key" do
    write(@acme, quota: nil, values: { "monthly_event_quota" => 500, "max_monitors" => 2 })
    write(@umbrella, quota: 900, values: { "monthly_event_quota" => nil })

    migrate(:down)

    assert_equal [ 500, { "max_monitors" => 2 } ], row(@acme)
    assert_equal [ nil, {} ], row(@umbrella), "a stored null is no quota"
    assert_equal [ nil, {} ], row(@fresh)
  end

  test "a round trip keeps a quota" do
    write(@acme, quota: nil, values: { "monthly_event_quota" => 42_000 })

    migrate(:down)
    migrate(:up)

    assert_equal [ 42_000, { "monthly_event_quota" => 42_000 } ], row(@acme)
  end

  test "Account ignores the column, and an INSERT naming it (the previous release) still works" do
    assert_not_includes Account.column_names, "monthly_event_quota"
    assert_nothing_raised { Account.create!(name: "Sign-up").reload }

    connection.exec_insert("INSERT INTO accounts (name, monthly_event_quota, entitlement_values, created_at, updated_at) " \
      "VALUES ('Previous', 5000, '{}', now(), now())")
    assert_equal 5_000, connection.select_value("SELECT monthly_event_quota FROM accounts WHERE name = 'Previous'")
  end

  private
    def connection = ActiveRecord::Base.connection

    def migrate(direction)
      ActiveRecord::Migration.suppress_messages { MoveMonthlyEventQuotaToEntitlements.new.migrate(direction) }
    end

    def write(id, quota:, values:)
      connection.exec_update("UPDATE accounts SET monthly_event_quota = #{connection.quote(quota)}, " \
        "entitlement_values = #{connection.quote(values.to_json)}::jsonb WHERE id = #{Integer(id)}")
    end

    def row(id)
      quota, values = connection.select_rows("SELECT monthly_event_quota, entitlement_values FROM accounts WHERE id = #{Integer(id)}").first
      [ quota&.to_i, JSON.parse(values) ]
    end
end
