require "test_helper"

class SlackIssueAlertTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = projects(:storefront)
    @issue = issues(:regressed)
  end

  def post_later(issue = @issue, kind = "regression", **options)
    SlackIssueAlert.new(issue, kind, **options).post_later
  end

  test "claims one post per event and enqueues the post job with the delivery id only" do
    delivery = nil
    assert_enqueued_jobs(1, only: SlackPostJob) { delivery = post_later }

    assert_predicate delivery, :sent?
    assert_equal [ @project.id, @issue.id, "regression", "slack:#{AlertDelivery.issue_key(:regression, @issue)}" ],
                 delivery.values_at(:project_id, :issue_id, :kind, :dedupe_key)
    assert_enqueued_with job: SlackPostJob, args: [ delivery.id ]
  end

  test "each instant kind posts while its rule is on" do
    AlertRule::INSTANT_KINDS.each do |kind|
      assert post_later(issues(:card_error), kind), kind
    end
  end

  test "posts nothing for the digest or an unknown kind" do
    assert_no_enqueued_jobs(only: SlackPostJob) do
      assert_nil post_later(@issue, "daily_digest")
      assert_nil post_later(@issue, "monitor_down")
    end
  end

  test "a second job for the same transition posts nothing" do
    post_later

    assert_no_enqueued_jobs(only: SlackPostJob) { assert_nil post_later }
  end

  test "posts nothing while the app's rule for the kind is off" do
    @project.alert_rules.find_by!(kind: "regression").update!(enabled: false)

    assert_no_enqueued_jobs(only: SlackPostJob) { assert_nil post_later }
  end

  test "posts nothing without a connection or while it is off" do
    slack_connections(:storefront).update!(enabled: false)
    assert_nil SlackIssueAlert.new(Issue.find(@issue.id), "regression").post_later

    slack_connections(:storefront).destroy!
    assert_nil SlackIssueAlert.new(Issue.find(@issue.id), "regression").post_later
    assert_no_enqueued_jobs only: SlackPostJob
  end

  test "posts nothing for resolved or ignored issues" do
    assert_nil post_later(issues(:resolved_issue), "new_issue")
    assert_nil post_later(issues(:ignored_issue), "new_issue")
  end

  test "follows the environment scope through the triggering occurrence" do
    @project.update!(alert_scope: "selected", alert_selected_environments: [ "staging" ])
    issue = issues(:nomethod)

    assert_nil post_later(issue, "reached_production", occurrence_id: occurrences(:nomethod_latest).id) # production

    @project.update!(alert_scope: "selected", alert_selected_environments: [ "production" ])
    assert post_later(Issue.find(issue.id), "reached_production", occurrence_id: occurrences(:nomethod_latest).id)
  end

  test "still happening posts at most once per 6 hours per issue" do
    issue = issues(:nomethod)
    assert post_later(issue, "still_happening")

    travel 3.hours
    assert_nil post_later(issue, "still_happening")

    travel 3.hours + 1.minute
    assert post_later(issue, "still_happening")
  end

  test "Slack and email are independent: muting every member's email still posts" do
    memberships(:alex_acme).update_notification_preference(@project, alerts_muted: true)
    memberships(:jo_acme).update_notification_preference(@project, alerts_muted: true)

    assert post_later
  end

  test "over the app's hourly cap, posts are folded for the summary instead of enqueued" do
    freeze_time
    SlackDelivery::HOURLY_CAP.times do |n|
      SlackDelivery.insert({ project_id: @project.id, kind: "new_issue", dedupe_key: "slack:cap-#{n}", status: "sent", created_at: Time.current })
    end

    delivery = nil
    assert_no_enqueued_jobs(only: SlackPostJob) { delivery = post_later }
    assert_predicate delivery, :folded?
  end

  test "still_due? re-checks the rule, status and scope when the post job runs" do
    alert = SlackIssueAlert.new(@issue, "regression")
    assert alert.still_due?

    @issue.update_columns(status: "resolved")
    assert_not SlackIssueAlert.new(@issue, "regression").still_due?
  end
end
