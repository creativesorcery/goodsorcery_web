require "test_helper"
require_relative "../../test_helpers/slack_test_helper"

class Projects::SlackConnectionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SlackTestHelper

  NEW_URL = "https://hooks.slack.com/services/T024BE7LD/B01ABCDEF2G/NewSecretValue1234567890".freeze

  setup do
    @project = projects(:storefront)
    sign_in_as users(:philip)
  end

  test "the Alerts page shows the connection masked, never the webhook URL" do
    get project_alerts_path(@project)

    assert_response :success
    assert_select "#slack h2", "Slack"
    assert_select "#slack .chip", "Connected"
    assert_select "#slack_connection", text: %r{https://hooks\.slack\.com/services/T0AC…/B0ST…/••••••••}
    assert_select "#slack form[action=?] button.toggle[aria-pressed=true][aria-label='Slack alerts']", project_slack_connection_path(@project)
    assert_select "#slack form[action='#{project_slack_connection_test_message_path(@project)}'] button", "Send test message"
    assert_select "#slack form[action='#{project_slack_connection_path(@project)}'] input[name=_method][value=delete]"
    assert_select "#slack input[type=url][name='slack_connection[webhook_url]']:not([value])"
    assert_select "#slack details summary", text: /How to get a webhook URL/
    assert_select "#slack a[href=?][target=_blank][rel='noopener noreferrer']", SlackConnection::DOCS_URL
    assert_not_includes response.body, SLACK_SECRET
    assert_not_includes response.body, "BillingRejectedSecret"
  end

  test "an app without Slack shows the connect form with the help open" do
    get project_alerts_path(projects(:marketing))

    assert_select "#slack .chip", 0
    assert_select "#slack input[type=submit][value='Connect Slack']"
    assert_select "#slack details[open]"
  end

  test "a webhook Slack rejected shows when and why" do
    travel_to slack_connections(:billing).disabled_at + 1.minute
    get project_alerts_path(projects(:billing))

    assert_select "#slack .chip", "Turned off by Slack"
    assert_select "#slack [role=status]", /Slack rejected the webhook on .*: the channel no longer exists/
    assert_select "#slack button.toggle[aria-pressed=false]"
  end

  test "connects an app by pasting a webhook URL" do
    patch project_slack_connection_path(projects(:marketing)), params: { slack_connection: { webhook_url: " #{NEW_URL} " } }

    assert_redirected_to project_alerts_path(projects(:marketing), anchor: "slack")
    assert_equal "Slack connected. Send a test message to check the channel.", flash[:notice]
    connection = projects(:marketing).reload.slack_connection
    assert_equal [ NEW_URL, true ], connection.values_at(:webhook_url, :enabled)
  end

  test "rejects a URL that isn't a Slack webhook, without echoing it back" do
    evil = "https://hooks.slack.com.evil.example/services/T024BE7LD/B01ABCDEF2G/EchoCanary12345"

    patch project_slack_connection_path(projects(:marketing)), params: { slack_connection: { webhook_url: evil } }

    assert_response :unprocessable_entity
    assert_select "#slack_webhook_url_error", /must be a Slack incoming webhook URL/
    assert_select "#slack input[name='slack_connection[webhook_url]'][aria-invalid=true]:not([value])"
    assert_not_includes response.body, "EchoCanary"
    assert_nil projects(:marketing).reload.slack_connection
  end

  test "a rejected replacement keeps the saved URL and shows its mask, not the new value" do
    patch project_slack_connection_path(@project), params: { slack_connection: { webhook_url: "http://hooks.slack.com/services/T1/B2/EchoCanary12345" } }

    assert_response :unprocessable_entity
    assert_select "#slack_connection", text: /T0AC…/
    assert_not_includes response.body, "EchoCanary"
    assert_equal WEBHOOK_URL, slack_connections(:storefront).reload.webhook_url
  end

  test "replacing the URL turns a rejected connection back on" do
    patch project_slack_connection_path(projects(:billing)), params: { slack_connection: { webhook_url: NEW_URL } }

    assert_equal "Slack webhook URL replaced.", flash[:notice]
    assert_equal [ NEW_URL, true, nil ], slack_connections(:billing).reload.values_at(:webhook_url, :enabled, :disabled_at)
  end

  test "switches posting off and on" do
    patch project_slack_connection_path(@project), params: { slack_connection: { enabled: false } }
    assert_equal "Slack alerts turned off.", flash[:notice]
    assert_not slack_connections(:storefront).reload.enabled?

    patch project_slack_connection_path(@project), params: { slack_connection: { enabled: true } }
    assert_equal "Slack alerts turned on.", flash[:notice]
    assert slack_connections(:storefront).reload.enabled?
  end

  test "disconnects" do
    delete project_slack_connection_path(@project)

    assert_redirected_to project_alerts_path(@project, anchor: "slack")
    assert_nil @project.reload.slack_connection
  end

  test "a member who isn't an owner can manage Slack, like the rest of Settings › Alerts" do
    sign_in_as users(:jo)

    patch project_slack_connection_path(@project), params: { slack_connection: { enabled: false } }
    assert_redirected_to project_alerts_path(@project, anchor: "slack")
    assert_not slack_connections(:storefront).reload.enabled?
  end

  test "the webhook URL is filtered from request logs" do
    log = capture_log do
      patch project_slack_connection_path(projects(:marketing)), params: { slack_connection: { webhook_url: NEW_URL } }
    end

    assert_includes log, "Parameters"
    assert_not_includes log, "NewSecretValue"
  end

  test "outsiders get 404 and change nothing" do
    sign_in_as users(:outsider)

    get project_alerts_path(@project)
    assert_response :not_found
    patch project_slack_connection_path(@project), params: { slack_connection: { webhook_url: NEW_URL } }
    assert_response :not_found
    patch project_slack_connection_path(@project), params: { slack_connection: { enabled: false } }
    assert_response :not_found
    delete project_slack_connection_path(@project)
    assert_response :not_found

    assert_equal [ WEBHOOK_URL, true ], slack_connections(:storefront).reload.values_at(:webhook_url, :enabled)
  end

  test "requires sign in" do
    sign_out

    patch project_slack_connection_path(@project), params: { slack_connection: { enabled: false } }
    assert_redirected_to new_session_path
    delete project_slack_connection_path(@project)
    assert_redirected_to new_session_path
  end
end
