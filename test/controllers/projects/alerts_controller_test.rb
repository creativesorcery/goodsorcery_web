require "test_helper"

class Projects::AlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    sign_in_as users(:philip)
  end

  test "requires sign in" do
    sign_out

    get project_alerts_path(@project)

    assert_redirected_to new_session_path
  end

  test "shows every rule with its switch, the threshold and the environment scope" do
    @project.update!(default_environment: "production")

    get project_alerts_path(@project)

    assert_response :success
    assert_select "h1", "Alerts"
    assert_select "nav[aria-label='Project settings'] a[aria-current=page]", "Alerts"
    assert_select "aside a.nav-link[aria-current=page][href=?]", project_alerts_path(@project)
    AlertRule::KINDS.each do |kind|
      assert_select "#alert_rule_#{kind} form[action=?] button.toggle", project_alert_rule_path(@project, kind)
    end
    assert_select "#alert_rule_new_issue button.toggle[aria-pressed=true]"
    assert_select "#alert_rule_daily_digest button.toggle[aria-pressed=false]"
    assert_select "#alert_rule_daily_digest input[name='alert_rule[enabled]'][value=true]"
    assert_select "#alert_rule_still_happening input[name='alert_rule[threshold]'][value='100']"
    assert_select "input[type=radio][name='project[alert_scope]'][value=follow_default][checked]"
    assert_select "label", text: /Follow the default environment \(production\)/
    assert_select "input[type=checkbox][name='project[alert_selected_environments][]'][value=staging]"
    assert_select "#alert_environments .text-coral-300", "production"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_match(/style="/, response.body)
  end

  test "a member who isn't an owner can see and change alerts, like Settings › General" do
    sign_in_as users(:jo)

    get project_alerts_path(@project)
    assert_response :success

    patch project_alerts_path(@project), params: { project: { alert_scope: "all" } }
    assert_redirected_to project_alerts_path(@project)
    assert @project.reload.alert_scope_all?
  end

  test "update saves a chosen set of environments" do
    patch project_alerts_path(@project),
          params: { project: { alert_scope: "selected", alert_selected_environments: [ "", "staging" ] } }

    assert_redirected_to project_alerts_path(@project)
    assert_equal "Alert environments saved.", flash[:notice]
    assert_equal [ "staging" ], @project.reload.alert_environments
  end

  test "update rejects an empty or unknown set and shows why" do
    patch project_alerts_path(@project), params: { project: { alert_scope: "selected", alert_selected_environments: [ "" ] } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", "Pick at least one environment."
    assert_select "#alert_environments_heading + p", /watch all environments/ # the saved scope, not the rejected one
    assert @project.reload.alert_scope_follow_default?

    patch project_alerts_path(@project), params: { project: { alert_scope: "selected", alert_selected_environments: [ "qa" ] } }
    assert_response :unprocessable_entity

    patch project_alerts_path(@project), params: { project: { alert_scope: "nowhere" } }
    assert_response :unprocessable_entity
  end

  test "update ignores other project attributes" do
    patch project_alerts_path(@project), params: { project: { alert_scope: "all", name: "renamed", retention_days: 5 } }

    assert_equal [ "storefront", 90 ], @project.reload.values_at(:name, :retention_days)
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_alerts_path(@project)
    assert_response :not_found

    patch project_alerts_path(@project), params: { project: { alert_scope: "all" } }
    assert_response :not_found
    assert @project.reload.alert_scope_follow_default?
  end
end
