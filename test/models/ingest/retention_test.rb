require "test_helper"

class Ingest::RetentionTest < ActiveSupport::TestCase
  def add_occurrence(issue, received_at)
    Occurrence.insert({ issue_id: issue.id, project_id: issue.project_id, uuid: SecureRandom.uuid_v7, occurred_at: received_at,
                        received_at:, environment: "production", level: "error", payload: "{}" }, returning: %i[id]).rows.first.first
  end

  test "prunes occurrences past each project's retention period" do
    storefront_old = add_occurrence(issues(:card_error), 91.days.ago)
    storefront_recent = add_occurrence(issues(:card_error), 89.days.ago)
    projects(:billing).update_column(:retention_days, 30)
    billing_old = add_occurrence(issues(:billing_timeout), 31.days.ago)

    Ingest::Retention.new.prune_occurrences

    assert_not Occurrence.exists?(storefront_old)
    assert_not Occurrence.exists?(billing_old)
    assert Occurrence.exists?(storefront_recent)
    assert Occurrence.exists?(occurrences(:nomethod_latest).id)
  end

  test "prunes hourly rollups older than 90 days" do
    old_hour = TimeSeries.align(91.days.ago, 1.hour)
    IssueHourlyCount.create!(issue: issues(:card_error), hour: old_hour, count: 3)
    ProjectHourlyCount.create!(project: projects(:storefront), environment: "production", hour: old_hour, count: 3)
    recent = IssueHourlyCount.count - 1

    Ingest::Retention.new.prune_rollups

    assert_not IssueHourlyCount.exists?(hour: ...90.days.ago)
    assert_not ProjectHourlyCount.exists?(hour: ...90.days.ago)
    assert_equal recent, IssueHourlyCount.count
  end
end
