require "test_helper"

class RecentFeedTest < ActiveSupport::TestCase
  test "lists unresolved issues seen in the last hour, newest first" do
    issues = RecentFeed.new(accounts(:acme)).entries.reject(&:resolved?).map(&:issue)

    assert_equal [ issues(:nomethod), issues(:regressed), issues(:card_error), issues(:billing_timeout) ], issues
  end

  test "skips ignored, resolved and older issues" do
    issues = RecentFeed.new(accounts(:acme)).entries.map(&:issue)

    assert_not_includes issues, issues(:ignored_issue)
    assert_not_includes issues, issues(:resolved_issue)
  end

  test "never includes another account's issues" do
    issues = RecentFeed.new(accounts(:acme)).entries.map(&:issue)

    assert_not_includes issues, issues(:umbrella_issue)
    assert_equal [ issues(:umbrella_issue) ], RecentFeed.new(accounts(:umbrella)).entries.map(&:issue)
  end

  test "classifies new, regressed and steady issues" do
    kinds = RecentFeed.new(accounts(:acme)).entries.to_h { |entry| [ entry.issue, entry.kind ] }

    assert_equal :new, kinds[issues(:nomethod)]
    assert_equal :regressed, kinds[issues(:regressed)]
    assert_equal :seen, kinds[issues(:card_error)]
  end

  test "merges resolutions from the last hour with their resolver" do
    issues(:card_error).resolve(by: users(:jo))
    entry = RecentFeed.new(accounts(:acme)).entries.find(&:resolved?)

    assert_equal issues(:card_error), entry.issue
    assert_equal users(:jo), entry.user
    assert_equal entry, RecentFeed.new(accounts(:acme)).entries.first
  end

  test "older resolutions are left out" do
    assert_not RecentFeed.new(accounts(:acme)).entries.any?(&:resolved?)
  end

  test "caps issues at eight and resolutions at four" do
    now = Time.current
    Issue.insert_all(9.times.map do |i|
      { project_id: projects(:storefront).id, number: 5_000 + i, fingerprint: SecureRandom.hex(32), exception_class: "RuntimeError",
        first_seen_at: now - 2.days, last_seen_at: now - 1.minute, created_at: now, updated_at: now }
    end)
    5.times { |i| IssueActivity.create!(issue: issues(:resolved_issue), kind: :resolved, created_at: now - i.minutes) }

    entries = RecentFeed.new(accounts(:acme)).entries

    assert_equal RecentFeed::ISSUE_LIMIT, entries.count { |entry| !entry.resolved? }
    assert_equal RecentFeed::RESOLUTION_LIMIT, entries.count(&:resolved?)
  end

  test "loads projects and resolvers without per-entry queries" do
    issues(:card_error).resolve(by: users(:jo))
    entries = RecentFeed.new(accounts(:acme)).entries

    assert_no_queries do
      entries.each { |entry| [ entry.issue.project.name, entry.user&.name ] }
    end
  end

  test "empty when nothing happened in the last hour" do
    assert_predicate RecentFeed.new(accounts(:acme), now: 3.days.from_now), :empty?
  end
end
