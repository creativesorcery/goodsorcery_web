require "test_helper"

class Projects::AlertRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    sign_in_as users(:philip)
  end

  test "requires sign in" do
    sign_out

    patch project_alert_rule_path(@project, "new_issue"), params: { alert_rule: { enabled: false } }

    assert_redirected_to new_session_path
    assert alert_rules(:storefront_new_issue).reload.enabled?
  end

  test "switches a rule off and on" do
    patch project_alert_rule_path(@project, "new_issue"), params: { alert_rule: { enabled: false } }

    assert_redirected_to project_alerts_path(@project)
    assert_not alert_rules(:storefront_new_issue).reload.enabled?

    patch project_alert_rule_path(@project, "daily_digest"), params: { alert_rule: { enabled: true } }
    assert alert_rules(:storefront_daily_digest).reload.enabled?
  end

  test "switches an uptime rule off, and an outsider can't" do
    patch project_alert_rule_path(@project, "monitor_down"), params: { alert_rule: { enabled: false } }

    assert_redirected_to project_alerts_path(@project)
    assert_not alert_rules(:storefront_monitor_down).reload.enabled?
    assert alert_rules(:storefront_monitor_recovered).reload.enabled?

    sign_in_as users(:outsider)
    patch project_alert_rule_path(@project, "monitor_recovered"), params: { alert_rule: { enabled: false } }
    assert_response :not_found
    assert alert_rules(:storefront_monitor_recovered).reload.enabled?
  end

  test "an uptime rule takes no threshold" do
    patch project_alert_rule_path(@project, "monitor_down"), params: { alert_rule: { threshold: "5" } }

    assert_response :unprocessable_entity
    assert_nil alert_rules(:storefront_monitor_down).reload.threshold
  end

  test "sets the still_happening threshold" do
    patch project_alert_rule_path(@project, "still_happening"), params: { alert_rule: { threshold: "250" } }

    assert_redirected_to project_alerts_path(@project)
    assert_equal 250, alert_rules(:storefront_still_happening).reload.threshold
  end

  test "rejects a bad threshold and shows the error on the page" do
    patch project_alert_rule_path(@project, "still_happening"), params: { alert_rule: { threshold: "0" } }

    assert_response :unprocessable_entity
    assert_select "#alert_rule_still_happening [role=alert]", "Threshold must be a whole number from 1 to 100,000"
    assert_select "#alert_rule_still_happening input[name='alert_rule[threshold]'][value='0'][aria-invalid=true].w-32"
    assert_equal 100, alert_rules(:storefront_still_happening).reload.threshold
  end

  test "a member who isn't an owner can change rules" do
    sign_in_as users(:jo)

    patch project_alert_rule_path(@project, "regression"), params: { alert_rule: { enabled: false } }

    assert_redirected_to project_alerts_path(@project)
    assert_not alert_rules(:storefront_regression).reload.enabled?
  end

  test "an unknown kind is 404" do
    patch project_alert_rule_path(@project, "pager"), params: { alert_rule: { enabled: false } }

    assert_response :not_found
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    patch project_alert_rule_path(@project, "new_issue"), params: { alert_rule: { enabled: false } }

    assert_response :not_found
    assert alert_rules(:storefront_new_issue).reload.enabled?
  end

  test "a rule of another account's app can't be reached through your own app" do
    sign_in_as users(:outsider)

    patch project_alert_rule_path(projects(:umbrella_app), "new_issue"), params: { alert_rule: { enabled: false } }

    assert_redirected_to project_alerts_path(projects(:umbrella_app))
    assert alert_rules(:storefront_new_issue).reload.enabled?
    assert_not alert_rules(:umbrella_app_new_issue).reload.enabled?
  end
end
