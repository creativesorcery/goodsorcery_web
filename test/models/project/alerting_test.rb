require "test_helper"

class Project::AlertingTest < ActiveSupport::TestCase
  setup { Current.session = sessions(:philip_browser) }
  teardown { Current.reset }

  test "a new app gets the default rule set" do
    project = accounts(:acme).projects.create!(name: "Fulfillment Workers")

    rules = project.alert_rules.order(:id).pluck(:kind, :enabled, :threshold)

    assert_equal [ [ "new_issue", true, nil ], [ "regression", true, nil ], [ "reached_production", true, nil ],
                   [ "still_happening", true, 100 ], [ "daily_digest", false, nil ] ], rules
  end

  test "alert_rule looks rules up by kind from one query" do
    project = projects(:storefront)

    assert_queries_count(1) do
      assert project.alert_rule(:new_issue).enabled?
      assert_not project.alert_rule("daily_digest").enabled?
      assert_equal 100, project.still_happening_threshold
      assert project.alert_rule_enabled?(:regression)
    end
  end

  test "alert_rule falls back to the default when a row is missing" do
    project = projects(:storefront)
    alert_rules(:storefront_daily_digest).destroy

    rule = project.alert_rule(:daily_digest)

    assert rule.new_record?
    assert_not rule.enabled?
  end

  test "alert_rules_in_order follows AlertRule::KINDS" do
    assert_equal AlertRule::KINDS, projects(:storefront).alert_rules_in_order.map(&:kind)
  end

  test "by default alerts follow the default environment" do
    project = projects(:storefront)

    project.default_environment = "production"
    assert project.alert_scope_follow_default?
    assert_equal [ "production" ], project.alert_environments

    project.default_environment = nil
    assert_nil project.alert_environments, "no default environment means all"
  end

  test "an app can watch all environments or a chosen set" do
    project = projects(:storefront)
    project.default_environment = "production"

    project.alert_scope = "all"
    assert_nil project.alert_environments

    project.alert_scope = "selected"
    project.alert_selected_environments = [ "Staging ", "", "staging" ]
    assert_equal [ "staging" ], project.alert_environments
  end

  test "a chosen set needs at least one of the app's environments" do
    project = projects(:storefront)
    project.alert_scope = "selected"

    project.alert_selected_environments = []
    assert_not project.valid?
    assert_equal [ "Pick at least one environment." ], project.errors.messages_for(:alert_selected_environments)

    project.alert_selected_environments = [ "qa" ]
    assert_not project.valid?
    assert_equal [ "Pick from this app's environments." ], project.errors.messages_for(:alert_selected_environments)

    project.alert_selected_environments = [ "production", "staging" ]
    assert project.valid?
  end

  test "picked environments are cleared when the scope is no longer selected" do
    project = projects(:storefront)
    project.update!(alert_scope: "selected", alert_selected_environments: [ "staging" ])

    project.update!(alert_scope: "follow_default")

    assert_empty project.reload.alert_selected_environments
  end

  test "saved_alert_environments ignores unsaved changes" do
    project = projects(:storefront)
    project.update!(default_environment: "production")
    project.assign_attributes(alert_scope: "selected", alert_selected_environments: [], default_environment: "staging")

    assert_empty project.alert_environments
    assert_equal [ "production" ], project.saved_alert_environments
  end

  test "an unknown scope is invalid" do
    project = projects(:storefront)
    project.alert_scope = "everywhere"

    assert_not project.valid?
  end

  test "alerts_cover? matches an event's or an issue's environments" do
    project = projects(:storefront)
    project.default_environment = "production"

    assert project.alerts_cover?("production")
    assert project.alerts_cover?(%w[staging production])
    assert_not project.alerts_cover?("staging")
    assert_not project.alerts_cover?([])

    project.alert_scope = "all"
    assert project.alerts_cover?("staging")
  end

  test "alert recipients are verified members who haven't muted the app" do
    users(:jo).update!(email_verified_at: nil)

    assert_equal [ users(:philip) ], projects(:storefront).alert_recipients.to_a

    users(:jo).update!(email_verified_at: Time.current)
    assert_equal [ users(:jo), users(:philip) ].sort_by(&:id), projects(:storefront).alert_recipients.order(:id).to_a
    assert_equal [ users(:philip) ], projects(:billing).alert_recipients.to_a, "jo muted billing"
  end

  test "digest recipients are verified members who haven't turned the digest off" do
    assert_equal 2, projects(:billing).digest_recipients.count, "muting alerts keeps the digest"

    memberships(:jo_acme).update_notification_preference(projects(:billing), digest_enabled: false)
    assert_equal [ users(:philip) ], projects(:billing).digest_recipients.to_a
  end

  test "outsiders never receive another account's alerts" do
    assert_not_includes projects(:storefront).alert_recipients, users(:outsider)
    assert_equal [ users(:outsider) ], projects(:umbrella_app).alert_recipients.to_a
  end
end
