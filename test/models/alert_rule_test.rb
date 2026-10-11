require "test_helper"

class AlertRuleTest < ActiveSupport::TestCase
  test "kinds and defaults" do
    assert_equal %w[new_issue regression reached_production still_happening daily_digest], AlertRule::KINDS
    assert_equal AlertRule::KINDS - %w[daily_digest], AlertRule::INSTANT_KINDS
    assert alert_rules(:storefront_new_issue).instant?
    assert_not alert_rules(:storefront_daily_digest).instant?
  end

  test "one rule per kind per app" do
    duplicate = projects(:storefront).alert_rules.new(kind: "new_issue")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:kind], "has already been taken"
  end

  test "an unknown kind is invalid" do
    assert_not AlertRule.new(project: projects(:storefront), kind: "pager").valid?
  end

  test "still_happening needs a whole-number threshold within range" do
    rule = alert_rules(:storefront_still_happening)

    [ nil, 0, -5, 1.5, AlertRule::THRESHOLD_RANGE.max + 1, "lots" ].each do |threshold|
      rule.threshold = threshold
      assert_not rule.valid?, "#{threshold.inspect} should be rejected"
    end

    [ 1, 250, AlertRule::THRESHOLD_RANGE.max ].each do |threshold|
      rule.threshold = threshold
      assert rule.valid?, "#{threshold} should be accepted"
    end
  end

  test "other rules have no threshold" do
    rule = alert_rules(:storefront_regression)
    rule.threshold = 10

    assert_not rule.valid?
  end

  test "the database rejects out-of-range thresholds too" do
    assert_raises(ActiveRecord::StatementInvalid) do
      alert_rules(:storefront_still_happening).update_column(:threshold, 0)
    end
  end

  test "to_param is the kind" do
    assert_equal "still_happening", alert_rules(:storefront_still_happening).to_param
  end

  test "enabled scope and kind scopes find the apps to check" do
    alert_rules(:billing_still_happening).update!(enabled: false)

    projects = AlertRule.enabled.still_happening.map(&:project)

    assert_includes projects, projects(:storefront)
    assert_not_includes projects, projects(:billing)
  end

  test "build_default is unsaved and stays out of the app's association" do
    project = projects(:storefront)
    rule = AlertRule.build_default(project, :still_happening)

    assert rule.new_record?
    assert_equal [ true, 100 ], [ rule.enabled, rule.threshold ]
    assert_not_includes project.alert_rules.to_a, rule
  end
end
