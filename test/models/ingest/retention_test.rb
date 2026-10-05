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

  test "prunes rollups by hour slice, never by composite key" do
    IssueHourlyCount.create!(issue: issues(:card_error), hour: TimeSeries.align(95.days.ago, 1.hour), count: 1)
    IssueHourlyCount.create!(issue: issues(:card_error), hour: TimeSeries.align(93.days.ago, 1.hour), count: 1)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].start_with?("DELETE") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { Ingest::Retention.new.prune_rollups }

    assert_not IssueHourlyCount.exists?(hour: ...90.days.ago)
    assert queries.any?
    assert queries.none? { it.include?(" OR ") }, "no OR'ed primary key pairs"
  end

  test "prunes affected users and tag values not seen within the retention period" do
    issue = issues(:card_error)
    issue.update_columns(last_seen_at: 100.days.ago)
    IssueUser.create!(issue:, project: issue.project, user_digest: "a" * 64, events_count: 1,
                                   first_seen_at: 100.days.ago, last_seen_at: 100.days.ago)
    IssueTagCount.create!(issue:, key: "user_email", value_digest: "b" * 64, value: "mara@example.com", count: 1)
    recent = issues(:nomethod)
    recent_tags = IssueTagCount.where(issue: recent).count

    Ingest::Retention.new.prune_issue_data

    assert_not IssueUser.exists?(issue_id: issue.id, user_digest: "a" * 64)
    assert_equal 0, IssueTagCount.where(issue:).count
    assert_equal recent_tags, IssueTagCount.where(issue: recent).count
  end

  test "deletes inbound events that never processed within a day" do
    old = inbound_events(:storefront_pending)
    old.update_columns(received_at: 2.days.ago)
    fresh = InboundEvent.create!(project: old.project, api_key: old.api_key, environment: "production",
                                 event_uuid: SecureRandom.uuid, body: "{}", received_at: 1.hour.ago)

    Ingest::Retention.new.prune_unprocessed

    assert_not InboundEvent.exists?(old.id)
    assert InboundEvent.exists?(fresh.id)
  end
end
