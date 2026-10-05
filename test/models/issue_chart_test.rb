require "test_helper"

class IssueChartTest < ActiveSupport::TestCase
  setup do
    @issue = issues(:nomethod)
  end

  test "24h has one bucket per hour from the fixtures" do
    chart = IssueChart.new(@issue)

    assert_equal "24h", chart.period
    assert_equal 24, chart.values.size
    assert_equal 32, chart.values.last
    assert_equal IssueHourlyCount.where(issue: @issue).sum(:count), chart.total
  end

  test "7d and 30d bucket sizes" do
    assert_equal 28, IssueChart.new(@issue, "7d").values.size
    assert_equal 30, IssueChart.new(issues(:card_error), "30d").values.size
  end

  test "unknown periods fall back to 24h" do
    assert_equal "24h", IssueChart.new(@issue, "<script>").period
    assert_equal "24h", IssueChart.new(@issue, nil).period
  end

  test "five axis labels ending in now" do
    travel_to Time.utc(2026, 10, 4, 9, 30) do
      labels = IssueChart.new(@issue).axis_labels

      assert_equal 5, labels.size
      assert_equal "10:00 yesterday", labels.first
      assert_equal "now", labels.last
    end
  end

  test "one title per bar" do
    chart = IssueChart.new(@issue)

    assert_equal 24, chart.titles.size
    assert_match(/· 32 events\z/, chart.titles.last)
  end

  test "caches only the numeric series, and only for 7d and 30d" do
    with_cache_store(ActiveSupport::Cache::MemoryStore.new) do |store|
      IssueChart.new(@issue, "7d").points
      IssueChart.new(@issue, "24h").points

      assert store.exist?([ "issue_chart", @issue.id, "7d" ])
      assert_not store.exist?([ "issue_chart", @issue.id, "24h" ])
      cached = store.read([ "issue_chart", @issue.id, "7d" ])
      assert(cached.all? { |time, count| time.is_a?(Time) && count.is_a?(Integer) })
    end
  end

  private
    def with_cache_store(store)
      original = Rails.cache
      Rails.cache = store
      yield store
    ensure
      Rails.cache = original
    end
end
