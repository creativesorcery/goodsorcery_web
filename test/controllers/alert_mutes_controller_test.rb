require "test_helper"

class AlertMutesControllerTest < ActionDispatch::IntegrationTest
  OLD_SAFARI = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 " \
               "(KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1".freeze

  setup do
    @user = users(:alex)
    @project = projects(:storefront)
    @token = @user.alert_mute_token(@project)
  end

  test "GET shows a confirmation page without signing in, and mutes nothing" do
    get alert_mute_path(token: @token)

    assert_response :success
    assert_select "h1", "Mute email alerts?"
    assert_select "form[action=?][method=post][data-turbo=false] input[name=token][value=?]", alert_mute_path, @token
    assert_select "*", text: /storefront/
    assert memberships(:alex_acme).receives_alerts?(@project)
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "POST mutes that app's alerts for that person" do
    post alert_mute_path, params: { token: @token }

    assert_response :success
    assert_select "h1", "Muted"
    assert_not memberships(:alex_acme).reload.receives_alerts?(@project)
    assert memberships(:alex_acme).receives_alerts?(projects(:billing))
    assert memberships(:jo_acme).receives_alerts?(@project)
  end

  test "RFC 8058 one-click POST works with the token in the URL and no CSRF token" do
    ActionController::Base.allow_forgery_protection = true

    post alert_mute_path(token: @token), params: "List-Unsubscribe=One-Click",
         headers: { "Content-Type" => "application/x-www-form-urlencoded" }

    assert_response :success
    assert_not memberships(:alex_acme).reload.receives_alerts?(@project)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "a digest link turns off the digest" do
    token = @user.alert_mute_token(@project, stream: "digest")

    get alert_mute_path(token:)
    assert_select "h1", "Mute the daily digest?"

    post alert_mute_path, params: { token: }
    assert_not memberships(:alex_acme).reload.receives_digest?(@project)
    assert memberships(:alex_acme).receives_alerts?(@project)
  end

  test "an uptime link turns off that app's uptime alerts only" do
    token = @user.alert_mute_token(@project, stream: "uptime")

    get alert_mute_path(token:)
    assert_response :success
    assert_select "h1", "Mute uptime alerts?"
    assert memberships(:alex_acme).receives_uptime_alerts?(@project)

    post alert_mute_path, params: { token: }
    assert_response :success
    assert_select "p", text: /won't get uptime alerts from\s+storefront/
    membership = memberships(:alex_acme).reload
    assert_not membership.receives_uptime_alerts?(@project)
    assert membership.receives_alerts?(@project)
    assert membership.receives_uptime_alerts?(projects(:billing))

    get alert_mute_path(token:)
    assert_select "h1", "Already off"
    assert_select "p", text: /Uptime alerts from\s+storefront\s+are off/
  end

  test "an uptime link sent as an RFC 8058 one-click POST works without a CSRF token" do
    ActionController::Base.allow_forgery_protection = true

    post alert_mute_path(token: @user.alert_mute_token(@project, stream: "uptime")), params: "List-Unsubscribe=One-Click",
         headers: { "Content-Type" => "application/x-www-form-urlencoded" }

    assert_response :success
    assert_not memberships(:alex_acme).reload.receives_uptime_alerts?(@project)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "an already muted app says so" do
    memberships(:alex_acme).update_notification_preference(@project, alerts_muted: true)

    get alert_mute_path(token: @token)

    assert_select "h1", "Already off"
    assert_select "form[action=?]", alert_mute_path, count: 0
  end

  test "an expired token is refused" do
    travel AlertMute::EXPIRES_IN + 1.minute do
      get alert_mute_path(token: @token)
      assert_response :not_found
      assert_select "h1", "This link no longer works"

      post alert_mute_path, params: { token: @token }
      assert_response :not_found
    end
    assert memberships(:alex_acme).reload.receives_alerts?(@project)
  end

  test "a tampered or missing token is refused" do
    post alert_mute_path, params: { token: "#{@token}x" }
    assert_response :not_found

    get alert_mute_path
    assert_response :not_found

    assert memberships(:alex_acme).reload.receives_alerts?(@project)
  end

  test "a token for another app mutes only that app" do
    post alert_mute_path, params: { token: @user.alert_mute_token(projects(:billing)) }

    assert memberships(:alex_acme).reload.receives_alerts?(@project)
    assert_not memberships(:alex_acme).receives_alerts?(projects(:billing))
  end

  test "an outsider's token can't reach another account's app" do
    post alert_mute_path, params: { token: AlertMute.token_for(users(:outsider), @project) }

    assert_response :not_found
    assert_equal 1, NotificationPreference.count
  end

  test "an old mobile browser can still confirm and mute (no modern-browser gate)" do
    headers = { "User-Agent" => OLD_SAFARI }

    get alert_mute_path(token: @token), headers: headers
    assert_response :success

    post alert_mute_path, params: { token: @token }, headers: headers
    assert_response :success
    assert_not memberships(:alex_acme).reload.receives_alerts?(@project)
  end

  test "the dashboard still turns old browsers away" do
    get new_session_path, headers: { "User-Agent" => OLD_SAFARI }

    assert_response :not_acceptable
  end

  test "the token is filtered from the request log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal "[FILTERED]", filter.filter("token" => @token)["token"]
  end
end
