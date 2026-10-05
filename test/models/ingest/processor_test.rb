require "test_helper"
require_relative "ingest_test_support"

class Ingest::ProcessorTest < ActiveSupport::TestCase
  include IngestTestSupport
  include ActiveJob::TestHelper

  setup do
    @project = projects(:storefront)
    @key = api_keys(:storefront_production)
  end

  test "creates a new issue with redacted summary columns and an occurrence" do
    issue = nil
    assert_difference -> { Issue.count } => 1, -> { Occurrence.count } => 1, -> { InboundEvent.count } => 0 do
      issue = process_event(event_json)
    end

    assert_equal 1046, issue.number
    assert_equal "NoMethodError", issue.exception_class
    assert_equal "undefined method `price_cents' for nil (cart [n], [email], card [FILTERED])", issue.message
    assert_equal "app/services/cart_total.rb:42 in line_total", issue.culprit
    assert_equal [ "production" ], issue.environments
    assert_equal [ 1, 1, "unresolved" ], [ issue.events_count, issue.users_count, issue.status ]
  end

  test "groups two events with the same fingerprint into one issue" do
    first = process_event(event_json)
    second = process_event(event_json("full", user: { id: 9, email: "jo@example.com", username: "jo" }))

    assert_equal first.id, second.id
    assert_equal 2, second.events_count
    assert_equal 2, second.users_count
    assert_equal 2, second.occurrences.count
  end

  test "a client fingerprint overrides default grouping" do
    a = process_event(minimal_json(exception: { class: "A" }, fingerprint: [ "checkout" ]))
    b = process_event(minimal_json(exception: { class: "B" }, fingerprint: [ "checkout" ]))
    c = process_event(minimal_json(exception: { class: "A" }))

    assert_equal a.id, b.id
    assert_not_equal a.id, c.id
  end

  test "adds new environments to an existing issue" do
    process_event(event_json)
    issue = process_event(event_json, key: api_keys(:storefront_staging))
    assert_equal %w[production staging], issue.environments
  end

  test "a resolved issue regresses, with a system activity" do
    issue = process_event(event_json)
    Issue.find(issue.id).resolve(by: users(:philip))

    regressed = nil
    assert_difference -> { IssueActivity.where(issue_id: issue.id, kind: "regressed", user_id: nil).count }, 1 do
      regressed = process_event(event_json)
    end
    assert regressed.unresolved?
    assert regressed.regressed?
    assert_nil regressed.resolved_at
    assert_equal "resolved", regressed.previous_status
  end

  test "ignored issues stay ignored" do
    issue = process_event(event_json)
    Issue.find(issue.id).ignore(by: users(:philip))
    assert process_event(event_json).ignored?
  end

  test "a duplicate event id is counted once and its inbound event is removed" do
    json = event_json("full", event_id: "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0cc3")
    issue = process_event(json)
    duplicate = inbound_event_for(json)

    assert_no_difference -> { Occurrence.count } do
      assert_nil Ingest::Processor.new(duplicate).process
    end
    assert_equal 1, issue.reload.events_count
    assert_not InboundEvent.exists?(duplicate.id)
  end

  test "records hourly, project, tag and user rollups" do
    issue = process_event(event_json)
    process_event(event_json)
    hour = TimeSeries.align(1.minute.ago, 1.hour)

    assert_equal 2, IssueHourlyCount.find_by(issue_id: issue.id, hour:).count
    assert_operator ProjectHourlyCount.find_by(project_id: @project.id, environment: "production", hour:).count, :>=, 2
    browser = IssueTagCount.find_by(issue_id: issue.id, key: "browser")
    assert_equal [ "Mobile Safari", 2 ], [ browser.value, browser.count ]
    assert_equal %w[browser build coupon environment host release], issue.tag_counts.pluck(:key).sort
    user = IssueUser.find_by(issue_id: issue.id)
    assert_equal [ 2, PrivateDigest.hexdigest("user.id", "5521") ], [ user.events_count, user.user_digest ]
    assert_equal 1, issue.reload.users_count
  end

  test "merges identity digests seen for the same user" do
    issue = process_event(minimal_json(user: { id: "77" }))
    process_event(minimal_json(user: { id: "77", email: "x@example.com" }))
    digests = IssueUser.find_by(issue_id: issue.id).identity_digests
    assert_includes digests, PrivateDigest.hexdigest("user.email", "x@example.com")
    assert_equal 2, digests.size
  end

  test "events without a user identity do not count users" do
    issue = process_event(minimal_json)
    assert_equal 0, issue.users_count
    assert_not IssueUser.exists?(issue_id: issue.id)
    assert_nil issue.occurrences.sole.user_digest
  end

  test "stores captured data encrypted" do
    issue = process_event(event_json)
    occurrence = issue.occurrences.sole
    assert_equal "[FILTERED]", occurrence.params["password"]
    assert_equal "Mara Lindqvist", occurrence.user["name"]

    raw_payload = raw_column(Occurrence, :payload, occurrence.id)
    assert_not_includes raw_payload, "mara"
    assert_not_includes raw_payload, "price_cents"
    tag = issue.tag_counts.find_by(key: "browser")
    assert_not_includes Occurrence.connection.select_value(
      IssueTagCount.where(issue_id: issue.id, key: "browser").select(:value).to_sql), "Safari"
    assert_equal "Mobile Safari", tag.value
  end

  test "marks the project's first event and runtime on a new issue" do
    project = projects(:marketing)
    process_event(minimal_json(context: { runtime: { rails: "8.1.0", ruby: "4.0.7" } }), key: api_keys(:marketing_production))
    project.reload
    assert_not project.listening?
    assert_equal "Rails 8.1 · Ruby 4.0", project.runtime_label
  end

  test "announces changes to the issue and project after commit" do
    calls = recording_broadcasts { @issue = process_event(event_json) }
    assert_includes calls, [ "Issue", @issue.id, { created: true } ]
    assert_includes calls, [ "Project", @project.id, {} ]

    calls = recording_broadcasts { process_event(event_json) }
    assert_includes calls, [ "Issue", @issue.id, { created: false } ]
  end

  test "enqueues trimming every 250 events" do
    issue = process_event(event_json)
    Issue.where(id: issue.id).update_all(events_count: 249)
    assert_enqueued_with(job: TrimOccurrencesJob, args: [ issue ]) { process_event(event_json) }
    assert_no_enqueued_jobs(only: TrimOccurrencesJob) { process_event(event_json) }
  end

  test "discards malformed inbound events without raising" do
    inbound = inbound_event_for('{"exception":{}}')
    assert_no_difference -> { Issue.count } do
      assert_nil Ingest::Processor.new(inbound).process
    end
    assert_not InboundEvent.exists?(inbound.id)
  end

  test "processes the pending fixture and removes it" do
    issue = Ingest::Processor.new(inbound_events(:storefront_pending)).process
    assert_equal "NoMethodError", issue.exception_class
    assert_equal "undefined method `price_cents' for nil", issue.message
    assert_not InboundEvent.exists?(inbound_events(:storefront_pending).id)
  end
end
