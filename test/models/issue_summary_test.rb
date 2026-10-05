require "test_helper"

class IssueSummaryTest < ActiveSupport::TestCase
  setup do
    @project = projects(:storefront)
  end

  test "24h events cover the trailing 24 hours, with the previous day as comparison" do
    freeze_time
    @elapsed = TimeSeries.elapsed_fraction(1.hour)
    summary = IssueSummary.new(@project)

    # storefront production: 120 this hour + 23 hours of 40..44; staging: 6;
    # plus the not-yet-elapsed share of the hour 24 hours ago.
    oldest = ProjectHourlyCount.where(project: @project, hour: TimeSeries.align(24.hours.ago, 1.hour)).sum(:count)
    expected = (120 + (1..23).sum { |i| 40 + (i % 5) } + 6 + (oldest * (1 - @elapsed))).round
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

  test "1h period counts the trailing 60 minutes and compares them with the 60 before" do
    freeze_time
    @elapsed = TimeSeries.elapsed_fraction(1.hour)
    summary = IssueSummary.new(@project, period: "1h", environment: "production")

    # This hour so far (120) plus the unelapsed share of the previous hour (41);
    # before that, the elapsed share of 41 and the rest of the hour before (42).
    events = (120 + (41 * (1 - @elapsed))).round
    previous = ((41 * @elapsed) + (42 * (1 - @elapsed))).round
    assert_equal events, summary.events
    assert_equal 12, summary.sparkline.size
    assert_equal ((events - previous) * 100.0 / previous).round, summary.events_change
  end

  test "an event half an hour ago counts in 1h early in the next hour" do
    project = projects(:marketing)
    travel_to Time.utc(2026, 10, 4, 10, 5) do
      ProjectHourlyCount.create!(project:, environment: "production", hour: Time.utc(2026, 10, 4, 9), count: 1)
      summary = IssueSummary.new(project, period: "1h")

      assert_equal 1, summary.events
      assert_nil summary.events_change, "no previous events, no misleading ▼ 100%"
    end
  end

  test "users affected on an environment-filtered summary counts users of that environment's issues" do
    staging = IssueSummary.new(@project, environment: "staging")
    staging_issue_ids = @project.issues.in_environment("staging").ids

    expected = IssueUser.where(project: @project, issue_id: staging_issue_ids, last_seen_at: 24.hours.ago..).distinct.count(:user_digest)
    assert_equal expected, staging.users_affected
    assert_operator IssueSummary.new(@project).users_affected, :>, staging.users_affected
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
