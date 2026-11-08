require "test_helper"

class Ingest::RetentionTest < ActiveSupport::TestCase
  def add_occurrence(issue, received_at)
    Occurrence.insert({ issue_id: issue.id, project_id: issue.project_id, uuid: SecureRandom.uuid_v7, occurred_at: received_at,
                        received_at:, environment: "production", level: "error", payload: "{}" }, returning: %i[id]).rows.first.first
  end

  test "prunes occurrences past each project's retention period" do
    storefront_old = add_occurrence(issues(:card_error), 31.days.ago)
    storefront_recent = add_occurrence(issues(:card_error), 29.days.ago)
    projects(:billing).update_column(:retention_days, 7)
    billing_old = add_occurrence(issues(:billing_timeout), 8.days.ago)
    billing_recent = add_occurrence(issues(:billing_timeout), 6.days.ago)

    Ingest::Retention.new.prune_occurrences

    assert_not Occurrence.exists?(storefront_old)
    assert_not Occurrence.exists?(billing_old)
    assert Occurrence.exists?(storefront_recent)
    assert Occurrence.exists?(billing_recent)
    assert Occurrence.exists?(occurrences(:nomethod_latest).id)
  end

  test "a retention stored above the cap is pruned at the cap" do
    projects(:storefront).update_column(:retention_days, 400)
    old = add_occurrence(issues(:card_error), (Project::MAX_RETENTION_DAYS + 1).days.ago)
    issue = issues(:card_error)
    issue.update_columns(last_seen_at: (Project::MAX_RETENTION_DAYS + 1).days.ago)
    IssueUser.create!(issue:, project: issue.project, user_digest: "a" * 64, events_count: 1,
                      first_seen_at: 100.days.ago, last_seen_at: 100.days.ago)

    Ingest::Retention.new.tap(&:prune_occurrences).prune_issue_data

    assert_not Occurrence.exists?(old)
    assert_not IssueUser.exists?(issue_id: issue.id, user_digest: "a" * 64)
  end

  test "a 90-day retention keeps occurrences for 90 days" do
    projects(:storefront).update_column(:retention_days, 90)
    kept = add_occurrence(issues(:card_error), 89.days.ago)
    pruned = add_occurrence(issues(:card_error), 91.days.ago)

    Ingest::Retention.new.prune_occurrences

    assert Occurrence.exists?(kept)
    assert_not Occurrence.exists?(pruned)
  end

  test "rollup windows follow the 30-day chart and uptime views, not the longest retention" do
    assert_equal 90, Project::MAX_RETENTION_DAYS
    assert_equal 31, Ingest::Retention::ISSUE_ROLLUP_DAYS
    assert_equal 31, Ingest::Retention::UPTIME_ROLLUP_DAYS
  end

  test "prunes issue counts after 31 days and project counts after 90" do
    issue_old = TimeSeries.align(32.days.ago, 1.hour)
    IssueHourlyCount.create!(issue: issues(:card_error), hour: issue_old, count: 3)
    ProjectHourlyCount.create!(project: projects(:storefront), environment: "production", hour: issue_old, count: 3)
    ProjectHourlyCount.create!(project: projects(:storefront), environment: "production",
                               hour: TimeSeries.align(91.days.ago, 1.hour), count: 3)
    recent = IssueHourlyCount.count - 1

    Ingest::Retention.new.prune_rollups

    assert_not IssueHourlyCount.exists?(hour: ...31.days.ago)
    assert_equal recent, IssueHourlyCount.count
    assert ProjectHourlyCount.exists?(hour: issue_old), "project counts outlive issue counts"
    assert_not ProjectHourlyCount.exists?(hour: ...90.days.ago)
  end

  test "prunes rollups by hour slice, never by composite key" do
    IssueHourlyCount.create!(issue: issues(:card_error), hour: TimeSeries.align(35.days.ago, 1.hour), count: 1)
    IssueHourlyCount.create!(issue: issues(:card_error), hour: TimeSeries.align(33.days.ago, 1.hour), count: 1)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].start_with?("DELETE") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { Ingest::Retention.new.prune_rollups }

    assert_not IssueHourlyCount.exists?(hour: ...31.days.ago)
    assert queries.any?
    assert queries.none? { it.include?(" OR ") }, "no OR'ed primary key pairs"
  end

  test "prunes affected users and tag values not seen within the retention period" do
    issue = issues(:card_error)
    issue.update_columns(last_seen_at: 40.days.ago)
    IssueUser.create!(issue:, project: issue.project, user_digest: "a" * 64, events_count: 1,
                                   first_seen_at: 40.days.ago, last_seen_at: 40.days.ago)
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

  test "deletes alert deliveries older than their keep window" do
    recent = alert_deliveries(:philip_nomethod_new_issue)
    old = travel_to(31.days.ago) do
      AlertDelivery.record(user: users(:jo), project: projects(:storefront), kind: :new_issue, dedupe_key: "old")
    end

    Ingest::Retention.new.prune_alert_deliveries

    assert_not AlertDelivery.exists?(old)
    assert AlertDelivery.exists?(recent.id)
  end

  test "keeps old down deliveries of uptime incidents still open" do
    open_incident = uptime_incidents(:storefront_api_outage)
    resolved = uptime_incidents(:storefront_home_timeout)
    kept, pruned = travel_to(31.days.ago) do
      [ open_incident, resolved ].map do |incident|
        AlertDelivery.record(user: users(:jo), project: projects(:storefront), kind: :monitor_down,
                             dedupe_key: AlertDelivery.incident_key("monitor_down", incident))
      end
    end

    Ingest::Retention.new.prune_alert_deliveries

    assert AlertDelivery.exists?(kept)
    assert_not AlertDelivery.exists?(pruned)
  end

  test "prunes uptime checks past the app's retention, never keeping more than 7 days" do
    home = uptime_monitors(:storefront_home)
    old = home.checks.create!(checked_at: (UptimeCheck::MAX_KEPT_DAYS + 1).days.ago, status: "up")
    kept = home.checks.create!(checked_at: (UptimeCheck::MAX_KEPT_DAYS - 1).days.ago, status: "up")
    projects(:billing).update_column(:retention_days, 2)
    billing = uptime_monitors(:billing_checkout)
    billing_old = billing.checks.create!(checked_at: 3.days.ago, status: "down", error_kind: "timeout")
    billing_kept = billing.checks.create!(checked_at: 1.day.ago, status: "up")

    Ingest::Retention.new.prune_uptime

    assert_not UptimeCheck.exists?(old.id)
    assert_not UptimeCheck.exists?(billing_old.id)
    assert UptimeCheck.exists?(kept.id)
    assert UptimeCheck.exists?(billing_kept.id)
    assert UptimeCheck.exists?(uptime_checks(:storefront_home_c0).id)
  end

  test "prunes uptime rollups after 31 days and resolved incidents after 31 days" do
    home = uptime_monitors(:storefront_home)
    UptimeHourlyCount.create!(uptime_monitor: home, hour: TimeSeries.align(32.days.ago, 1.hour), checks_count: 6, up_count: 6)
    UptimeHourlyCount.create!(uptime_monitor: home, hour: TimeSeries.align(30.days.ago, 1.hour), checks_count: 6, up_count: 6)
    old = home.incidents.create!(started_at: 40.days.ago, resolved_at: 32.days.ago)
    recent = home.incidents.create!(started_at: 20.days.ago, resolved_at: 20.days.ago + 5.minutes)
    open = uptime_incidents(:storefront_api_outage).tap { it.update_columns(started_at: 40.days.ago) }

    Ingest::Retention.new.prune

    assert_not UptimeHourlyCount.exists?(hour: ...31.days.ago)
    assert UptimeHourlyCount.exists?(uptime_monitor_id: home.id, hour: TimeSeries.align(30.days.ago, 1.hour))
    assert_not UptimeIncident.exists?(old.id)
    assert UptimeIncident.exists?(recent.id)
    assert UptimeIncident.exists?(open.id), "open incidents are kept"
  end

  # Performance data (docs/ARCHITECTURE.md §13.7).

  def apm_stat_row(model, transaction, time)
    { apm_transaction_id: transaction.id, model.time_column => time, requests_count: 1 }
  end

  def add_apm_trace(transaction, minute)
    ApmTrace.insert({ project_id: transaction.project_id, apm_transaction_id: transaction.id, uuid: Apm::TraceId.generate(minute),
                      minute:, hour: TimeSeries.align(minute, 1.hour), started_at: minute, payload: "{}", created_at: minute },
                    returning: %i[id]).rows.first.first
  end

  test "prunes per-minute performance rows after 2 days" do
    checkout = apm_transactions(:checkout_create)
    old, kept = TimeSeries.align(50.hours.ago, 1.minute), TimeSeries.align(47.hours.ago, 1.minute)
    ApmMinuteStat.insert_all([ apm_stat_row(ApmMinuteStat, checkout, old), apm_stat_row(ApmMinuteStat, checkout, kept) ])

    Ingest::Retention.new.prune_apm

    assert_not ApmMinuteStat.exists?(apm_transaction_id: checkout.id, minute: old)
    assert ApmMinuteStat.exists?(apm_transaction_id: checkout.id, minute: kept)
  end

  test "prunes hourly performance rows, traces and stale transactions past each account's retention" do
    checkout, umbrella = apm_transactions(:checkout_create), apm_transactions(:umbrella_home)
    hour = TimeSeries.align(10.days.ago, 1.hour)
    ApmHourlyStat.insert_all([ apm_stat_row(ApmHourlyStat, checkout, hour), apm_stat_row(ApmHourlyStat, umbrella, hour) ])
    old_trace, umbrella_trace = add_apm_trace(checkout, hour), add_apm_trace(umbrella, hour)
    stale = ApmTransaction.create!(project: projects(:storefront), environment: "production", kind: "web", name: "Old#gone",
                                   first_seen_at: 40.days.ago, last_seen_at: 31.days.ago)

    with_hosted_mode do
      accounts(:umbrella).update!(entitlement_values: accounts(:umbrella).entitlement_values.merge("apm_retention_days" => 14))
      Ingest::Retention.new.prune_apm
    end

    assert_not ApmHourlyStat.exists?(apm_transaction_id: checkout.id, hour:), "acme has the hosted default of 1 day"
    assert_not ApmTrace.exists?(old_trace)
    assert ApmHourlyStat.exists?(apm_transaction_id: umbrella.id, hour:), "umbrella keeps 14 days"
    assert ApmTrace.exists?(umbrella_trace)
    assert_not ApmTransaction.exists?(stale.id)
    assert ApmTransaction.exists?(checkout.id)
    assert ApmTrace.exists?(apm_traces(:checkout_failed).id)
    assert ApmTransaction.exists?(apm_transactions(:storefront_web_total).id), "total rows stay"
  end

  test "self-hosted keeps performance data for the instance setting" do
    checkout = apm_transactions(:checkout_create)
    hour = TimeSeries.align(10.days.ago, 1.hour)
    ApmHourlyStat.insert_all([ apm_stat_row(ApmHourlyStat, checkout, hour) ])

    Ingest::Retention.new.prune_apm
    assert ApmHourlyStat.exists?(apm_transaction_id: checkout.id, hour:)

    Rails.configuration.x.apm_retention_days, previous = 7, Rails.configuration.x.apm_retention_days
    Ingest::Retention.new.prune_apm
    assert_not ApmHourlyStat.exists?(apm_transaction_id: checkout.id, hour:)
  ensure
    Rails.configuration.x.apm_retention_days = previous if previous
  end

  test "a backstop deletes anything older than the longest retention" do
    checkout = apm_transactions(:checkout_create)
    hour = TimeSeries.align(40.days.ago, 1.hour)
    ApmHourlyStat.insert_all([ apm_stat_row(ApmHourlyStat, checkout, hour) ])
    trace = add_apm_trace(checkout, hour)
    Ingest::Retention.new.prune_apm_backstop
    assert_not ApmTrace.exists?(trace)
    assert_not ApmHourlyStat.exists?(apm_transaction_id: checkout.id, hour:)
  end

  test "deletes inbound performance batches after a day, logging unprocessed ids only" do
    old = apm_inbound_batches(:storefront_pending_metrics)
    old.update_columns(received_at: 25.hours.ago)
    log = StringIO.new
    previous, Rails.logger = Rails.logger, ActiveSupport::Logger.new(log)

    Ingest::Retention.new.prune_apm

    assert_not ApmInboundBatch.exists?(old.id)
    assert_includes log.string, old.id.to_s
    assert_not_includes log.string, "Checkouts"
  ensure
    Rails.logger = previous
  end
end
