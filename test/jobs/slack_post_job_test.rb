require "test_helper"
require_relative "../test_helpers/slack_test_helper"

class SlackPostJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include SlackTestHelper

  setup do
    @project = projects(:storefront)
    @issue = issues(:regressed)
    @delivery = SlackDelivery.record(project: @project, kind: :regression, issue: @issue)
  end

  test "runs on the alerts queue" do
    assert_equal "alerts", SlackPostJob.new.queue_name
    assert_equal "alerts", SlackTestMessageJob.new.queue_name
  end

  test "a 2xx posts the alert to the app's webhook and marks it posted" do
    with_fake_slack(slack_result(:delivered, 200)) do |slack|
      SlackPostJob.perform_now(@delivery.id)

      assert_equal [ WEBHOOK_URL ], slack.urls
      assert_equal "Regression in storefront: #{@issue.message}", slack.payloads.sole[:text]
    end
    assert_predicate @delivery.reload, :posted?
    assert_no_enqueued_jobs only: SlackPostJob
  end

  test "a duplicate job doesn't post again" do
    @delivery.mark_posted

    with_fake_slack do |slack|
      SlackPostJob.perform_now(@delivery.id)
      assert_empty slack.payloads
    end
  end

  test "a 429 retries after Slack's Retry-After" do
    freeze_time
    with_fake_slack(slack_result(:retry, 429, retry_after: 42)) { SlackPostJob.perform_now(@delivery.id) }

    assert_enqueued_with job: SlackPostJob, args: [ @delivery.id ], at: 42.seconds.from_now
    assert_not @delivery.reload.posted?
  end

  test "a 5xx or network error retries with backoff, then gives up" do
    freeze_time
    with_fake_slack(slack_result(:retry, 503)) { SlackPostJob.perform_now(@delivery.id) }
    assert_enqueued_with job: SlackPostJob, args: [ @delivery.id ], at: 30.seconds.from_now

    clear_enqueued_jobs
    job = SlackPostJob.new(@delivery.id).tap { |last| last.executions = SlackPostJob::MAX_ATTEMPTS - 1 }
    with_fake_slack(slack_result(:retry, reason: "Net::ReadTimeout")) { job.perform_now }
    assert_no_enqueued_jobs only: SlackPostJob
  end

  test "a 404 or 410 turns the connection off, records why and emails the owners once" do
    other = SlackDelivery.record(project: @project, kind: :new_issue, issue: issues(:card_error))
    freeze_time

    assert_enqueued_emails 1 do
      with_fake_slack(slack_result(:rejected, 404, reason: "no_service")) { SlackPostJob.perform_now(@delivery.id) }
      with_fake_slack do |slack| # now off: not posted
        SlackPostJob.perform_now(other.id)
        assert_empty slack.payloads
      end
    end

    connection = slack_connections(:storefront).reload
    assert_equal [ false, Time.current, "no_service" ], connection.values_at(:enabled, :disabled_at, :disabled_reason)
    assert_enqueued_email_with AlertsMailer, :slack_disabled, args: [ users(:philip), @project ]
    assert_no_enqueued_jobs only: SlackPostJob
  end

  test "another 4xx drops the post without retrying or turning Slack off" do
    with_fake_slack(slack_result(:failed, 400)) { SlackPostJob.perform_now(@delivery.id) }

    assert_no_enqueued_jobs only: SlackPostJob
    assert_predicate slack_connections(:storefront).reload, :enabled?
  end

  test "re-checks at send time: resolved issue, rule off, connection off or gone" do
    with_fake_slack do |slack|
      @issue.update_columns(status: "resolved")
      SlackPostJob.perform_now(@delivery.id)

      @issue.update_columns(status: "unresolved")
      @project.alert_rules.find_by!(kind: "regression").update!(enabled: false)
      SlackPostJob.perform_now(@delivery.id)

      @project.alert_rules.find_by!(kind: "regression").update!(enabled: true)
      slack_connections(:storefront).destroy!
      SlackPostJob.perform_now(@delivery.id)

      assert_empty slack.payloads
    end
  end

  test "posts uptime alerts and summaries" do
    down = SlackDelivery.record(project: @project, kind: :monitor_down, uptime_incident: uptime_incidents(:storefront_api_outage))
    summary = SlackDelivery.record(project: @project, kind: :summary, summary_counts: { "new_issue" => 4 })

    with_fake_slack(slack_result(:delivered, 200), slack_result(:delivered, 200)) do |slack|
      SlackPostJob.perform_now(down.id)
      SlackPostJob.perform_now(summary.id)

      assert_equal [ "Down: Storefront API in storefront", "And 4 more alerts in storefront in the last hour" ], slack.payloads.pluck(:text)
    end
  end

  test "a missing delivery does nothing" do
    with_fake_slack do |slack|
      SlackPostJob.perform_now(0)
      assert_empty slack.payloads
    end
  end

  test "logs the outcome and status, never the webhook URL" do
    log = capture_log do
      with_fake_slack(slack_result(:retry, 429, retry_after: 5)) { SlackPostJob.perform_now(@delivery.id) }
    end

    assert_includes log, "SlackPostJob delivery=#{@delivery.id} kind=regression outcome=retry status=429"
    assert_not_includes log, SLACK_SECRET
    assert_not_includes log, "hooks.slack.com"
  end

  test "job arguments are ids and kinds only, never the webhook URL" do
    IssueAlertJob.perform_now(issues(:card_error).id, "new_issue")
    UptimeAlertJob.perform_now(uptime_incidents(:storefront_api_outage).id, "monitor_down")

    args = enqueued_jobs.map { |job| job["arguments"] }.to_s
    assert_not_includes args, SLACK_SECRET
    assert_not_includes args, "hooks.slack.com"
    assert_enqueued_jobs 2, only: SlackPostJob
  end

  test "the test message job posts once and turns off a rejected webhook" do
    connection = slack_connections(:storefront)
    with_fake_slack(slack_result(:delivered, 200)) do |slack|
      SlackTestMessageJob.perform_now(connection.id)
      assert_includes slack.payloads.sole[:text], "Good Sorcery is connected"
    end

    log = capture_log do
      with_fake_slack(slack_result(:rejected, 403, reason: "invalid_token")) { SlackTestMessageJob.perform_now(connection.id) }
    end
    assert_equal "rejected", connection.reload.status
    assert_not_includes log, SLACK_SECRET
    assert_no_enqueued_jobs only: SlackTestMessageJob
  end
end
