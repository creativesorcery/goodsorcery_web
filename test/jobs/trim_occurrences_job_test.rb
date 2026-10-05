require "test_helper"

class TrimOccurrencesJobTest < ActiveJob::TestCase
  test "keeps the newest RETAINED_PER_ISSUE occurrences of the issue only" do
    issue = issues(:card_error)
    now = Time.current
    rows = Array.new(Occurrence::RETAINED_PER_ISSUE + 3) do
      { issue_id: issue.id, project_id: issue.project_id, uuid: SecureRandom.uuid_v7, occurred_at: now, received_at: now,
        environment: "production", level: "error", payload: "{}" }
    end
    Occurrence.insert_all(rows)
    newest_ids = issue.occurrences.latest_first.limit(Occurrence::RETAINED_PER_ISSUE).ids
    other_issue_count = issues(:nomethod).occurrences.count

    TrimOccurrencesJob.perform_now(issue)

    assert_equal newest_ids.sort, issue.occurrences.ids.sort
    assert_equal other_issue_count, issues(:nomethod).occurrences.count
  end

  test "does nothing under the limit" do
    assert_no_difference(-> { Occurrence.count }) { TrimOccurrencesJob.perform_now(issues(:nomethod)) }
  end
end
