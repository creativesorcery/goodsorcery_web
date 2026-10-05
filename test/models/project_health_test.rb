require "test_helper"

class ProjectHealthTest < ActiveSupport::TestCase
  setup do
    @now = Time.current.end_of_hour # the last 60 minutes are this clock hour
  end

  test "listening when no event has arrived, whatever the numbers" do
    health = health_for(projects(:marketing), unresolved: 4, hourly: steady_hours + [ 500 ])

    assert_equal :listening, health.status
    assert_predicate health, :listening?
  end

  test "all clear with nothing unresolved" do
    health = health_for(projects(:billing), unresolved: 0, hourly: steady_hours + [ 500 ])

    assert_equal :all_clear, health.status
    assert_predicate health, :all_clear?
  end

  test "spiking at ten or more events and three times the previous average" do
    assert_predicate health_for(projects(:storefront), unresolved: 3, hourly: steady_hours(4) + [ 12 ]), :spiking?
    assert_predicate health_for(projects(:storefront), unresolved: 3, hourly: steady_hours(0) + [ 10 ]), :spiking?
  end

  test "early in an hour, the last 60 minutes include most of the previous hour" do
    @now = Time.utc(2026, 10, 4, 10, 5)
    # 30 events between 09:00 and 10:00, 2 since 10:00, a quiet day before.
    assert_predicate health_for(projects(:storefront), unresolved: 3, hourly: Array.new(22, 1) + [ 30, 2 ]), :spiking?

    @now = Time.utc(2026, 10, 4, 10, 59)
    assert_predicate health_for(projects(:storefront), unresolved: 3, hourly: Array.new(22, 1) + [ 30, 2 ]), :steady?
  end

  test "steady below the spike minimum even from a quiet baseline" do
    assert_predicate health_for(projects(:storefront), unresolved: 3, hourly: steady_hours(0) + [ 9 ]), :steady?
  end

  test "steady below three times the previous average" do
    assert_predicate health_for(projects(:storefront), unresolved: 3, hourly: steady_hours(40) + [ 119 ]), :steady?
  end

  test "steady with no hourly data at all" do
    assert_predicate health_for(projects(:storefront), unresolved: 1, hourly: []), :steady?
  end

  test "days clean counts whole days since the last error" do
    health = health_for(projects(:billing), unresolved: 0, last_seen_at: @now - 12.days - 3.hours)

    assert_equal 12, health.days_clean
  end

  test "days clean falls back to the first event without any issue" do
    project = projects(:billing)
    health = health_for(project, unresolved: 0, last_seen_at: nil)

    assert_equal ((@now - project.first_event_at) / 1.day).floor, health.days_clean
  end

  test "days clean is never negative" do
    assert_equal 0, health_for(projects(:billing), unresolved: 0, last_seen_at: @now + 2.minutes).days_clean
  end

  private
    def steady_hours(count = 4)
      Array.new(23, count)
    end

    def health_for(project, unresolved:, hourly: steady_hours + [ 4 ], last_seen_at: @now - 1.hour)
      ProjectHealth.new(project, unresolved_count: unresolved, hourly_totals: hourly, last_seen_at:, now: @now)
    end
end
