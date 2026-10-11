require "test_helper"
require_relative "ingest_test_support"

class Ingest::IssueTallyTest < ActiveSupport::TestCase
  include IngestTestSupport

  setup do
    @project = projects(:storefront)
    @event = build_event(minimal_json)
  end

  test "creates once, then finds the existing issue" do
    first = Ingest::IssueTally.new(@project, @event)
    id = first.find_or_create_issue_id
    assert first.created?

    second = Ingest::IssueTally.new(@project, @event)
    assert_no_difference -> { Issue.count } do
      assert_equal id, second.find_or_create_issue_id
    end
    assert_not second.created?
  end

  test "losing the insert race falls back to the winner's issue" do
    winner_id = Ingest::IssueTally.new(@project, @event).find_or_create_issue_id

    loser = Ingest::IssueTally.new(@project, @event)
    lookups = 0
    real_lookup = loser.method(:existing_issue_id)
    loser.define_singleton_method(:existing_issue_id) { (lookups += 1) == 1 ? nil : real_lookup.call }

    assert_no_difference -> { Issue.count } do
      assert_equal winner_id, loser.find_or_create_issue_id
    end
    assert_not loser.created?
    assert_equal 2, lookups
  end

  test "count updates counters atomically and returns the previous status" do
    tally = Ingest::IssueTally.new(@project, @event)
    tally.find_or_create_issue_id
    issue = tally.count(new_user: true)

    assert_equal [ 1, 1, "unresolved" ], [ issue.events_count, issue.users_count, issue.previous_status ]
    assert_same @project, issue.project
    assert_equal 2, tally.count(new_user: false).events_count
  end

  test "count stamps reached_production_at once, for any production-like environment" do
    staging = Ingest::IssueTally.new(@project, build_event(minimal_json, environment: "staging"))
    staging.find_or_create_issue_id
    assert_nil staging.count(new_user: false).reached_production_at

    live = Ingest::IssueTally.new(@project, build_event(minimal_json, environment: "live"))
    live.find_or_create_issue_id
    first = live.count(new_user: false)
    second = live.count(new_user: false)

    assert first.just_reached_production
    assert_not second.just_reached_production
    assert_equal first.reached_production_at, second.reached_production_at
    assert_equal %w[staging live], second.environments
  end

  test "count never stamps an issue already seen in production" do
    production = Ingest::IssueTally.new(@project, build_event(minimal_json, environment: "prod"))
    production.find_or_create_issue_id
    production.count(new_user: false)
    Issue.where(id: production.issue_id).update_all(environments: %w[prod staging])

    again = Ingest::IssueTally.new(@project, build_event(minimal_json, environment: "production"))
    again.find_or_create_issue_id
    issue = again.count(new_user: false)

    assert_nil issue.reached_production_at
    assert_not issue.just_reached_production
  end
end
