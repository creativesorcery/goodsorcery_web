require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:jo) }

  test "requires sign in" do
    sign_out

    get notifications_path

    assert_redirected_to new_session_path
  end

  test "lists the account's apps with the member's own switches and time zone" do
    users(:jo).update!(time_zone: "Europe/Berlin")
    alert_rules(:storefront_daily_digest).update!(enabled: true)

    get notifications_path

    assert_response :success
    assert_select "h1", "Notifications"
    assert_select "#digest_time_zone", "Europe/Berlin"
    assert_select "li[id^=notifications_project_]", 3
    assert_select "##{dom_id(projects(:billing), :notifications)}" do
      assert_select "button.toggle[aria-label='Email alerts from billing-api'][aria-pressed=false]"
      assert_select "input[name='notification_preference[alerts_muted]'][value=false]"
      # billing-api's digest rule is off: no switch that suggests a digest is coming.
      assert_select "button.toggle[aria-label='Daily digest from billing-api']", 0
      assert_select "a[href=?]", project_alerts_path(projects(:billing)), text: "Off for this app"
      # Muting billing-api's issue alerts keeps its uptime alerts.
      assert_select "button.toggle[aria-label='Uptime alerts from billing-api'][aria-pressed=true]"
      assert_select "input[name='notification_preference[uptime_alerts_muted]'][value=true]"
    end
    assert_select "span", "Uptime alerts"
    assert_select "##{dom_id(projects(:storefront), :notifications)} button.toggle[aria-pressed=true]", 3
    assert_no_match "umbrella-app", response.body
    assert_no_match(/style="/, response.body)
  end

  test "the uptime switch shows off when the app sends no uptime alerts" do
    memberships(:jo_acme).update_notification_preference(projects(:storefront), uptime_alerts_muted: true)

    get notifications_path
    assert_select "##{dom_id(projects(:storefront), :notifications)} button.toggle[aria-label='Uptime alerts from storefront'][aria-pressed=false]"

    alert_rules(:storefront_monitor_down).update!(enabled: false)
    alert_rules(:storefront_monitor_recovered).update!(enabled: false)
    get notifications_path

    assert_select "##{dom_id(projects(:storefront), :notifications)}" do
      assert_select "button.toggle[aria-label='Uptime alerts from storefront']", 0
      assert_select "a[title*='sends no uptime alerts']", "Off for this app"
    end
  end

  test "renders in a fixed number of queries however many apps there are" do
    get notifications_path
    baseline = count_queries { get notifications_path }

    3.times { |n| accounts(:acme).projects.create!(name: "extra #{n}") }

    assert_equal baseline, count_queries { get notifications_path }
  end

  test "tells an unverified member that alerts start once they confirm" do
    users(:jo).update!(email_verified_at: nil)

    get notifications_path

    assert_select "p", text: /Alert emails start once you confirm your email address/
  end

  test "the user menu links here" do
    get projects_path

    assert_select "a.menu-item[href=?]", notifications_path, text: /Notifications/
  end

  private
    def count_queries(&)
      queries = []
      # Cached queries count too: the test connection's query cache can outlive a request.
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
      queries.size
    end
end
