require "test_helper"
require Rails.root.join("db/migrate/20261011000001_create_alert_rules")

# Postgres DDL is transactional, so the test's rollback restores the table.
class CreateAlertRulesTest < ActiveSupport::TestCase
  teardown { AlertRule.reset_column_information }

  test "every existing app gets the default rule set" do
    migration = CreateAlertRules.new.tap { |m| m.verbose = false }
    migration.migrate(:down)
    migration.migrate(:up)
    AlertRule.reset_column_information

    # This migration backfills the original five rules; AddUptimeAlerts adds the uptime ones.
    assert_equal Project.count * CreateAlertRules::DEFAULTS.size, AlertRule.count
    rules = projects(:billing).alert_rules.order(:id).pluck(:kind, :enabled, :threshold)
    assert_equal CreateAlertRules::DEFAULTS, rules
  end
end
