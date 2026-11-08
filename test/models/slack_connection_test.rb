require "test_helper"
require_relative "../test_helpers/slack_test_helper"

class SlackConnectionTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include SlackTestHelper

  VALID = "https://hooks.slack.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678".freeze

  def connection_with(url)
    SlackConnection.new(project: projects(:marketing), webhook_url: url)
  end

  test "accepts a webhook URL in the shape Slack issues, trimming spaces" do
    connection = connection_with("  #{VALID}\n")

    assert connection.valid?, connection.errors.full_messages.to_sentence
    assert_equal VALID, connection.webhook_url
  end

  test "rejects anything else, without echoing the value" do
    [
      "", "http://hooks.slack.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "https://hooks.slack.com.evil.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "https://evil.com/hooks.slack.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "https://evilhooks.slack.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "https://hooks.slack.com:8443/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "https://user:pass@hooks.slack.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "https://hooks.slack.com@evil.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "#{VALID}?channel=general", "#{VALID}#x", "#{VALID}/", "#{VALID}/extra",
      "https://hooks.slack.com/workflows/T024BE7LD/A01/123/abcdEFGH1234",
      "https://hooks.slack.com/services/x024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "https://hooks.slack.com/services/T024BE7LD/B01ABCDEF2G/abcd-EFGH%2F1234",
      "https://HOOKS.SLACK.COM/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234ijklMNOP5678",
      "https://hooks.slack.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234\nhttps://evil.com",
      "javascript:alert(1)//https://hooks.slack.com/services/T024BE7LD/B01ABCDEF2G/abcdEFGH1234"
    ].each do |url|
      connection = connection_with(url)

      assert_not connection.valid?, "accepted #{url.inspect}"
      assert connection.errors[:webhook_url].any?
      assert_not_includes connection.errors.full_messages.join, "abcdEFGH1234"
    end
  end

  test "one connection per app" do
    duplicate = SlackConnection.new(project: projects(:storefront), webhook_url: VALID)

    assert_not duplicate.valid?
  end

  test "the URL is ciphertext at rest and never in inspect output" do
    raw = SlackConnection.connection.select_value("SELECT webhook_url FROM slack_connections WHERE id = #{slack_connections(:storefront).id}")

    assert_not_includes raw, SLACK_SECRET
    assert_not_includes raw, "hooks.slack.com"
    assert_equal WEBHOOK_URL, slack_connections(:storefront).webhook_url
    assert_not_includes slack_connections(:storefront).inspect, SLACK_SECRET
  end

  test "masks the URL to the first characters of the team and bot ids" do
    masked = slack_connections(:storefront).masked_webhook_url

    assert_equal "https://hooks.slack.com/services/T0AC…/B0ST…/••••••••", masked
    assert_not_includes masked, "Secret"
  end

  test "status: connected, off, or rejected by Slack" do
    assert_equal "connected", slack_connections(:storefront).status
    assert_equal "rejected", slack_connections(:billing).status
    assert_equal "the channel no longer exists", slack_connections(:billing).rejection_label

    slack_connections(:storefront).update!(enabled: false)
    assert_equal "off", slack_connections(:storefront).status
  end

  test "switching back on or pasting a new URL clears the rejection" do
    billing = slack_connections(:billing)
    billing.update!(enabled: true)
    assert_equal [ true, nil, nil ], billing.reload.values_at(:enabled, :disabled_at, :disabled_reason)

    billing.update_columns(enabled: false, disabled_at: Time.current, disabled_reason: "invalid_token")
    billing.update!(webhook_url: VALID)
    assert_equal [ true, nil, nil ], billing.reload.values_at(:enabled, :disabled_at, :disabled_reason)
  end

  test "turning off after a rejection records when and why and emails each verified owner once" do
    connection = slack_connections(:storefront)
    freeze_time

    assert_enqueued_emails 1 do
      assert connection.turn_off_after_rejection("channel_not_found")
      assert_not connection.turn_off_after_rejection("channel_not_found")
    end
    assert_enqueued_email_with AlertsMailer, :slack_disabled, args: [ users(:philip), projects(:storefront) ]
    assert_equal [ false, Time.current, "channel_not_found" ], connection.reload.values_at(:enabled, :disabled_at, :disabled_reason)
  end

  test "owners to notify are verified owners only" do
    users(:philip).update_columns(email_verified_at: nil)

    assert_empty slack_connections(:storefront).owners_to_notify
    assert_equal [ users(:outsider) ], SlackConnection.new(project: projects(:umbrella_app)).owners_to_notify.to_a
  end

  test "one test message per gap, however many ask" do
    connection = slack_connections(:storefront)
    freeze_time

    assert connection.claim_test_message
    assert_not SlackConnection.find(connection.id).claim_test_message

    travel SlackConnection::TEST_MESSAGE_GAP
    assert SlackConnection.find(connection.id).claim_test_message
  end

  test "deleting the app deletes its connection" do
    assert_difference -> { SlackConnection.count }, -1 do
      SlackConnection.connection.execute("DELETE FROM projects WHERE id = #{projects(:storefront).id}")
    end
  end
end
