require "test_helper"

class Projects::NotificationPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    sign_in_as users(:jo)
  end

  test "requires sign in" do
    sign_out

    patch project_notification_preference_path(@project), params: { notification_preference: { alerts_muted: true } }

    assert_redirected_to new_session_path
  end

  test "mutes and unmutes an app's alerts for the signed-in member only" do
    patch project_notification_preference_path(@project), params: { notification_preference: { alerts_muted: true } }

    assert_redirected_to notifications_path
    assert_equal "Notification settings saved.", flash[:notice]
    assert_not memberships(:jo_acme).receives_alerts?(@project)
    assert memberships(:philip_acme).receives_alerts?(@project)

    patch project_notification_preference_path(@project), params: { notification_preference: { alerts_muted: false } }
    assert memberships(:jo_acme).reload.receives_alerts?(@project)
  end

  test "mutes and unmutes an app's uptime alerts, keeping its issue alerts" do
    patch project_notification_preference_path(@project), params: { notification_preference: { uptime_alerts_muted: true } }

    assert_redirected_to notifications_path
    assert_not memberships(:jo_acme).receives_uptime_alerts?(@project)
    assert memberships(:jo_acme).receives_alerts?(@project)
    assert memberships(:philip_acme).receives_uptime_alerts?(@project)

    patch project_notification_preference_path(@project), params: { notification_preference: { uptime_alerts_muted: false } }
    assert memberships(:jo_acme).reload.receives_uptime_alerts?(@project)
  end

  test "turns the digest off" do
    patch project_notification_preference_path(@project), params: { notification_preference: { digest_enabled: false } }

    assert_not memberships(:jo_acme).receives_digest?(@project)
    assert memberships(:jo_acme).receives_alerts?(@project)
  end

  test "doesn't change the sidebar's remembered project" do
    get project_issues_path(projects(:billing))
    patch project_notification_preference_path(@project), params: { notification_preference: { alerts_muted: true } }
    follow_redirect!

    assert_select "aside [data-controller=dropdown] button", text: /billing-api/
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    patch project_notification_preference_path(@project), params: { notification_preference: { alerts_muted: true } }
    assert_response :not_found

    patch project_notification_preference_path(@project), params: { notification_preference: { uptime_alerts_muted: true } }
    assert_response :not_found
    assert_equal 1, NotificationPreference.count
  end
end
