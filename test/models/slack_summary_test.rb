require "test_helper"

class SlackSummaryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    travel_to Time.utc(2026, 11, 8, 10, 2)
    @project = projects(:storefront)
  end

  def fold(kind, issue, at: 1.hour.ago)
    SlackDelivery.record(project: @project, kind:, issue:, status: "folded", at:)
  end

  test "one summary post per app for last hour's folded posts, with counts per kind" do
    fold(:new_issue, issues(:resolved_issue))
    fold(:new_issue, issues(:card_error))
    fold(:regression, issues(:regressed))
    current = fold(:new_issue, issues(:ignored_issue), at: 1.minute.ago)

    assert_enqueued_jobs(1, only: SlackPostJob) { SlackSummary.post_due }

    summary = SlackDelivery.find_by!(kind: "summary")
    assert_equal({ "new_issue" => 2, "regression" => 1 }, summary.summary_counts)
    assert_equal [ @project.id, "sent" ], summary.values_at(:project_id, :status)
    assert_enqueued_with job: SlackPostJob, args: [ summary.id ]
    assert_nil current.reload.summarized_at # waits for the next hour
    assert_equal 3, SlackDelivery.folded.where.not(summarized_at: nil).count
  end

  test "a repeated run in the same hour posts nothing more" do
    fold(:new_issue, issues(:resolved_issue))
    SlackSummary.post_due
    fold(:new_issue, issues(:card_error))

    assert_no_enqueued_jobs(only: SlackPostJob) { SlackSummary.post_due }
    assert_equal 1, SlackDelivery.summary.count
  end

  test "nothing to summarise posts nothing" do
    assert_no_enqueued_jobs(only: SlackPostJob) { SlackSummary.post_due }
  end

  test "SendAlertSummariesJob runs it" do
    fold(:new_issue, issues(:resolved_issue))

    assert_enqueued_jobs(1, only: SlackPostJob) { SendAlertSummariesJob.perform_now }
  end
end
