require "test_helper"
require_relative "ingest_test_support"

# Ingest only flags alert transitions: one IssueAlertJob per transition,
# enqueued after commit with integer ids and the rule kind (ARCHITECTURE.md §11.4).
class Ingest::AlertFlagsTest < ActiveSupport::TestCase
  include IngestTestSupport
  include ActiveJob::TestHelper

  test "a brand-new issue flags new_issue once, with the occurrence that created it" do
    issue = nil
    assert_enqueued_jobs 1, only: IssueAlertJob do
      issue = process_event(event_json)
    end
    assert_equal [ [ issue.id, "new_issue", issue.occurrences.sole.id ] ], alert_job_args

    clear_enqueued_jobs
    assert_no_enqueued_jobs(only: IssueAlertJob) { process_event(event_json) }
  end

  test "a regression flags regression once" do
    issue = process_event(event_json)
    Issue.find(issue.id).resolve(by: users(:philip))
    clear_enqueued_jobs

    regressed = process_event(event_json)
    assert_equal [ [ issue.id, "regression", regressed.occurrences.latest.id ] ], alert_job_args

    clear_enqueued_jobs
    assert_no_enqueued_jobs(only: IssueAlertJob) { process_event(event_json) }
  end

  test "reaching production flags reached_production once" do
    staging = process_event(event_json, key: api_keys(:storefront_staging))
    assert_equal [ [ staging.id, "new_issue", staging.occurrences.sole.id ] ], alert_job_args
    clear_enqueued_jobs

    production = process_event(event_json)
    assert_equal [ [ staging.id, "reached_production", production.occurrences.latest.id ] ], alert_job_args

    clear_enqueued_jobs
    process_event(event_json)
    process_event(event_json, key: api_keys(:storefront_staging))
    assert_empty alert_job_args
  end

  test "a resolved staging issue regressing in production flags both rules" do
    issue = process_event(event_json, key: api_keys(:storefront_staging))
    Issue.find(issue.id).resolve(by: users(:philip))
    clear_enqueued_jobs

    process_event(event_json)
    assert_equal %w[reached_production regression], alert_job_args.map(&:second).sort
  end

  test "events of an ignored issue flag nothing" do
    issue = process_event(event_json)
    Issue.find(issue.id).ignore(by: users(:philip))
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: IssueAlertJob) { process_event(event_json) }
  end

  test "a duplicate event flags nothing" do
    json = event_json("full", event_id: "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0dd4")
    process_event(json)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: IssueAlertJob) { process_event(json) }
  end

  test "job arguments are integer ids and the kind, never captured data" do
    issue = process_event(event_json, key: api_keys(:storefront_staging))
    Issue.find(issue.id).resolve(by: users(:philip))
    process_event(event_json)

    jobs = enqueued_jobs.select { |job| job["job_class"] == "IssueAlertJob" }
    assert_equal 3, jobs.size
    jobs.each do |job|
      issue_id, kind, occurrence_id = job["arguments"]
      assert_kind_of Integer, issue_id
      assert_includes AlertRule::INSTANT_KINDS, kind
      assert_kind_of Integer, occurrence_id
    end
    serialized = jobs.map { |job| job["arguments"] }.to_json
    [ "price_cents", "mara", "NoMethodError", "cart_total", "CheckoutsController" ].each { |text| assert_not_includes serialized, text }
  end

  test "an ordinary event of an existing issue adds no queries and touches no alert table" do
    process_event(event_json)
    clear_enqueued_jobs
    inbound = inbound_event_for(event_json)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { Ingest::Processor.new(inbound).process }

    # issue SELECT, SAVEPOINT, occurrence, issue hour, tag lookup and upsert,
    # issue user, counter UPDATE, inbound DELETE, project hour, RELEASE, and
    # the account read by the live-update broadcast.
    assert_equal 12, statements.size, statements.join("\n")
    assert_no_match(/alert|notification_preferences|memberships/, statements.join("\n"))
    assert_empty alert_job_args
  end

  private
    def alert_job_args
      enqueued_jobs.select { |job| job["job_class"] == "IssueAlertJob" }.map { |job| job["arguments"] }
    end
end
