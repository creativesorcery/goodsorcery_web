require "application_system_test_case"

class AlertsSystemTest < ApplicationSystemTestCase
  setup do
    @project = projects(:storefront)
    sign_in
  end

  test "switching a rule off and on in Settings › Alerts" do
    visit_connected project_alerts_path(@project)
    assert_selector "#alert_rule_new_issue button.toggle[aria-pressed=true]"

    press find("#alert_rule_new_issue button.toggle")

    assert_text "Alert rules saved."
    assert_selector "#alert_rule_new_issue button.toggle[aria-pressed=false]"
    assert_selector "#alert_rule_new_issue .chip", text: "off"
    assert_not alert_rules(:storefront_new_issue).reload.enabled?

    press find("#alert_rule_new_issue button.toggle")

    assert_selector "#alert_rule_new_issue button.toggle[aria-pressed=true]"
    assert alert_rules(:storefront_new_issue).reload.enabled?
  end

  test "setting the still-happening threshold and choosing environments" do
    visit_connected project_alerts_path(@project)

    type_into find_field("Threshold"), "250"
    press find("#alert_rule_still_happening input[type=submit]")
    assert_text "Alert rules saved."
    assert_equal 250, alert_rules(:storefront_still_happening).reload.threshold

    press find("input[type=radio][value=selected]")
    press find("#alert_environment_staging")
    press find_button("Save environments")

    assert_text "Alert environments saved."
    assert_selector "#alert_environments_heading + p", text: "The issue rules above watch staging."
    assert_equal [ "staging" ], @project.reload.alert_environments
  end

  test "muting an app from the Notifications page in the user menu" do
    visit_connected projects_path
    user_menu = find("aside [data-controller=dropdown]", text: users(:philip).name)
    press user_menu.find("button")
    press user_menu.find_link("Notifications")
    assert_current_path notifications_path

    press find("button.toggle[aria-label='Email alerts from storefront']")

    assert_text "Notification settings saved."
    assert_selector "button.toggle[aria-label='Email alerts from storefront'][aria-pressed=false]"
    assert_not memberships(:philip_acme).receives_alerts?(@project)
  end

  test "the mute link from an email confirms, then mutes" do
    visit alert_mute_path(token: users(:jo).alert_mute_token(@project))
    assert_selector "h1", text: "Mute email alerts?"

    press find_button("Mute email alerts")

    assert_selector "h1", text: "Muted"
    assert_not memberships(:jo_acme).reload.receives_alerts?(@project)
  end
end
