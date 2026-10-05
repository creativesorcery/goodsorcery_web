require "test_helper"

class IssueSummaryTest < ActiveSupport::TestCase
  setup do
    @project = projects(:storefront)
  end

  test "24h events with the previous day as comparison" do
    summary = IssueSummary.new(@project)

    # storefront production: 120 this hour + 23 hours of 40..44; staging: 6.
    expected = 120 + (1..23).sum { |i| 40 + (i % 5) } + 6
    assert_equal "24h", summary.period.key
    assert_equal expected, summary.events
    assert_equal 24, summary.sparkline.size
  end

  test "environment narrows events and issue counts" do
    summary = IssueSummary.new(@project, environment: "staging")

    assert_equal 6, summary.events
    assert_equal 1, summary.unresolved_count
    assert_equal 1, summary.regressions
  end

  test "an invalid environment is ignored" do
    assert_nil IssueSummary.new(@project, environment: "Prod'; --").environment
  end

  test "unknown periods fall back to 24h" do
    assert_equal "24h", IssueSummary.new(@project, period: "5y").period.key
  end

  test "1h period compares the current hour with the one before" do
    summary = IssueSummary.new(@project, period: "1h", environment: "production")

    assert_equal 120, summary.events
    assert_equal 12, summary.sparkline.size
    assert_equal ((120 - 41) * 100.0 / 41).round, summary.events_change
  end

  test "change is nil without events in the previous period" do
    assert_nil IssueSummary.new(projects(:marketing)).events_change
  end

  test "issue numbers" do
    summary = IssueSummary.new(@project)

    assert_equal 3, summary.unresolved_count
    assert_equal 1, summary.new_issues
    assert_equal 0, summary.new_last_hour
    assert_equal 1, summary.regressions
    assert_equal 2, summary.users_affected
  end

  test "users affected spans the period" do
    assert_equal 1, IssueSummary.new(@project, period: "1h").users_affected
  end

  test "caches only numbers, keyed by project, environment and period" do
    store = ActiveSupport::Cache::MemoryStore.new
    with_cache(store) { IssueSummary.new(@project, environment: "production").events }

    cached = store.read([ "summary", @project.id, "production", "24h" ])
    assert_equal %i[events previous_events sparkline new_issues new_last_hour regressions users_affected].sort, cached.keys.sort
    assert cached.values.flatten.all?(Integer)
  end

  private
    def with_cache(store)
      original = Rails.cache
      Rails.cache = store
      yield
    ensure
      Rails.cache = original
    end
end
