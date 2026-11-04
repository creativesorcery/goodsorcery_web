require "test_helper"
require Rails.root.join("db/migrate/20261103000003_add_uptime_alerts")

# Postgres DDL is transactional, so the test's rollback restores the schema.
class AddUptimeAlertsTest < ActiveSupport::TestCase
  teardown do
    AlertRule.reset_column_information
    NotificationPreference.reset_column_information
  end

  test "every existing app gets both uptime rules, switched on, and members get the uptime switch" do
    migration.migrate(:down)
    NotificationPreference.reset_column_information
    assert_not NotificationPreference.column_names.include?("uptime_alerts_muted")
    assert_equal 0, AlertRule.where(kind: AlertRule::UPTIME_KINDS).count

    migration.migrate(:up)
    NotificationPreference.reset_column_information

    assert_not notification_preferences(:jo_billing).reload.uptime_alerts_muted?
    assert_equal Project.count * 2, AlertRule.where(kind: AlertRule::UPTIME_KINDS, enabled: true, threshold: nil).count
    assert_equal AlertRule::UPTIME_KINDS, projects(:billing).alert_rules.where(kind: AlertRule::UPTIME_KINDS).order(:kind).pluck(:kind)
  end

  test "running it again adds nothing and fills in only what is missing" do
    alert_rules(:storefront_monitor_down).update!(enabled: false)
    alert_rules(:billing_monitor_recovered).delete

    assert_difference -> { AlertRule.count }, 1 do
      migration.migrate(:up)
      migration.migrate(:up)
    end

    assert_equal Project.count * AlertRule::KINDS.size, AlertRule.count
    assert_not alert_rules(:storefront_monitor_down).reload.enabled?, "an existing rule keeps its setting"
  end

  private
    def migration
      @migration ||= AddUptimeAlerts.new.tap { |m| m.verbose = false }
    end
end
