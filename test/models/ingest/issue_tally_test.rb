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
end
