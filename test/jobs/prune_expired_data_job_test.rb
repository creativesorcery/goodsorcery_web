require "test_helper"

class PruneExpiredDataJobTest < ActiveJob::TestCase
  test "prunes occurrences past their project's retention" do
    issue = issues(:card_error)
    old_id = Occurrence.insert({ issue_id: issue.id, project_id: issue.project_id, uuid: SecureRandom.uuid_v7, occurred_at: 91.days.ago,
                                 received_at: 91.days.ago, environment: "production", level: "error", payload: "{}" }, returning: %i[id]).rows.first.first

    PruneExpiredDataJob.perform_now

    assert_not Occurrence.exists?(old_id)
    assert Occurrence.exists?(occurrences(:nomethod_latest).id)
  end
end
