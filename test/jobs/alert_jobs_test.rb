require "test_helper"

class AlertJobsTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "the alert jobs run on the alerts queue" do
    [ IssueAlertJob, CheckStillHappeningJob, SendDailyDigestsJob, SendAlertSummariesJob ].each do |job|
      assert_equal "alerts", job.new.queue_name
    end
  end

  test "IssueAlertJob delivers the alert for the issue and kind" do
    issue = issues(:regressed)

    assert_enqueued_emails(2) { IssueAlertJob.perform_now(issue.id, "regression", occurrences(:regressed_latest).id) }
    assert_equal 2, AlertDelivery.where(issue:, kind: "regression").count
  end

  test "IssueAlertJob looks the triggering occurrence up once for email and Slack" do
    issue, occurrence_id = issues(:regressed), occurrences(:regressed_latest).id

    assert_queries_match(/FROM "occurrences"/, count: 1) do
      IssueAlertJob.perform_now(issue.id, "regression", occurrence_id)
    end
    assert_equal 1, SlackDelivery.where(issue:, kind: "regression").count
  end

  test "IssueAlertJob doesn't look the occurrence up when the rule is off" do
    projects(:storefront).alert_rules.find_by!(kind: "regression").update!(enabled: false)
    issue_id, occurrence_id = issues(:regressed).id, occurrences(:regressed_latest).id

    assert_no_queries_match(/FROM "occurrences"/) do
      IssueAlertJob.perform_now(issue_id, "regression", occurrence_id)
    end
  end

  test "IssueAlertJob does nothing for an issue that no longer exists" do
    assert_no_enqueued_emails { IssueAlertJob.perform_now(0, "new_issue") }
  end

  test "the scheduled jobs call into their domain objects" do
    travel_to Time.utc(2026, 10, 14, 10, 2)
    AlertDelivery.record(user: users(:jo), project: projects(:storefront), kind: :new_issue, dedupe_key: "folded",
                         status: "folded").then { |id| AlertDelivery.where(id:).update_all(created_at: 1.hour.ago) }

    assert_enqueued_emails(1) { SendAlertSummariesJob.perform_now }
    assert_nothing_raised { CheckStillHappeningJob.perform_now }
    assert_nothing_raised { SendDailyDigestsJob.perform_now }
  end
end
