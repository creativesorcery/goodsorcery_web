require "test_helper"

class StillHappeningCheckTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # 10:15, a quarter into the hour: the trailing hour is this hour's count
  # plus three quarters of the previous hour's.
  NOW = Time.utc(2026, 10, 14, 10, 15)

  setup do
    travel_to NOW
    IssueHourlyCount.delete_all
    Issue.update_all(last_seen_at: 3.days.ago)
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    @project.alert_rules.find_by!(kind: "still_happening").update!(threshold: 50)
  end

  test "an issue whose trailing-hour events reach the threshold is hot" do
    seen(@issue, current: 20, previous: 40) # 20 + 40 × 0.75 = 50

    assert_equal [ @issue.id ], StillHappeningCheck.new.hot_issue_ids
  end

  test "below the threshold is not hot" do
    seen(@issue, current: 19, previous: 40) # 49

    assert_empty StillHappeningCheck.new.hot_issue_ids
  end

  test "each app uses its own threshold" do
    seen(@issue, current: 60)
    seen(issues(:billing_timeout), current: 60) # billing-api keeps the default 100

    assert_equal [ @issue.id ], StillHappeningCheck.new.hot_issue_ids
  end

  test "ignored and resolved issues and apps with the rule off are never hot" do
    seen(issues(:ignored_issue), current: 500)
    seen(issues(:resolved_issue), current: 500)
    seen(issues(:umbrella_issue), current: 500)
    projects(:umbrella_app).alert_rules.find_by!(kind: "still_happening").update!(enabled: false)

    assert_empty StillHappeningCheck.new.hot_issue_ids
  end

  test "enqueues one alert job per hot issue, with the id and kind only" do
    seen(@issue, current: 80)

    assert_enqueued_with(job: IssueAlertJob, args: [ @issue.id, "still_happening" ]) do
      assert_equal [ @issue ], StillHappeningCheck.new.alert_hot_issues
    end
  end

  test "skips issues alerted in the last 6 hours, then alerts again" do
    seen(@issue, current: 80)
    AlertDelivery.record(user: users(:jo), project: @project, issue: @issue, kind: :still_happening,
                         dedupe_key: AlertDelivery.issue_key(:still_happening, @issue))

    assert_no_enqueued_jobs(only: IssueAlertJob) { StillHappeningCheck.new.alert_hot_issues }

    travel 6.hours + 1.minute
    seen(@issue, current: 80)
    assert_enqueued_jobs(1, only: IssueAlertJob) { StillHappeningCheck.new.alert_hot_issues }
  end

  test "skips issues outside the app's environment scope" do
    @project.update!(alert_scope: "selected", alert_selected_environments: [ "staging" ])
    seen(@issue, current: 80) # production only

    assert_no_enqueued_jobs(only: IssueAlertJob) { StillHappeningCheck.new.alert_hot_issues }
  end

  test "end to end: the job mails each recipient once per window" do
    seen(@issue, current: 80)

    perform_enqueued_jobs(only: IssueAlertJob) { StillHappeningCheck.new.alert_hot_issues }
    assert_equal 2, AlertDelivery.where(issue: @issue, kind: "still_happening", status: "sent").count
    assert_enqueued_jobs 2, only: ActionMailer::MailDeliveryJob

    perform_enqueued_jobs(only: IssueAlertJob) { StillHappeningCheck.new.alert_hot_issues }
    assert_equal 2, AlertDelivery.where(issue: @issue, kind: "still_happening").count
  end

  private
    def seen(issue, current:, previous: 0)
      hour = Time.current.beginning_of_hour
      issue.update_columns(last_seen_at: Time.current)
      IssueHourlyCount.upsert({ issue_id: issue.id, hour:, count: current }, record_timestamps: false)
      IssueHourlyCount.upsert({ issue_id: issue.id, hour: hour - 1.hour, count: previous }, record_timestamps: false) if previous.positive?
    end
end
