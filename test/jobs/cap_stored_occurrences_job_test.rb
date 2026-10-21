require "test_helper"

class CapStoredOccurrencesJobTest < ActiveJob::TestCase
  test "holds each project to RETAINED_PER_PROJECT stored occurrences" do
    issue = issues(:card_error)
    now = Time.current
    rows = Array.new(Occurrence::RETAINED_PER_PROJECT) do
      { issue_id: issue.id, project_id: issue.project_id, uuid: SecureRandom.uuid_v7, occurred_at: now, received_at: now,
        environment: "production", level: "error", payload: "{}" }
    end
    Occurrence.insert_all(rows)
    other_issues = Occurrence.where(project: issue.project).where.not(issue:).count

    CapStoredOccurrencesJob.perform_now

    assert_equal Occurrence::RETAINED_PER_PROJECT, Occurrence.where(project: issue.project).count
    assert_equal other_issues, Occurrence.where(project: issue.project).where.not(issue:).count
  end
end
