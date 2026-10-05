require "test_helper"
require Rails.root.join("test/test_helpers/live_cache_test_helper")

class LiveUpdateGateTest < ActiveSupport::TestCase
  include LiveCacheTestHelper

  test "first_in_window? is true once per window" do
    gate = LiveUpdateGate.new(:issue, 1)

    assert gate.first_in_window?
    assert_not gate.first_in_window?
    assert_not LiveUpdateGate.new(:issue, 1).first_in_window?

    travel LiveUpdateGate::WINDOW + 1.second
    assert gate.first_in_window?
  end

  test "keys are separate per kind and id" do
    assert LiveUpdateGate.new(:issue, 1).first_in_window?
    assert LiveUpdateGate.new(:issue, 2).first_in_window?
    assert LiveUpdateGate.new(:project, 1).first_in_window?
  end

  test "within_limit? lets the first callers through, then resets after the window" do
    gate = LiveUpdateGate.new(:new_issues, 1)

    assert_equal [ true, true, true, false, false ], Array.new(5) { gate.within_limit?(3) }

    travel LiveUpdateGate::WINDOW + 1.second
    assert gate.within_limit?(3)
  end

  test "the cache holds only a counter under an id-based key" do
    LiveUpdateGate.new(:issue, 42).first_in_window?

    assert_equal 1, Rails.cache.read([ "live", "issue", 42 ])
  end

  test "a null store lets everything through" do
    Rails.cache = ActiveSupport::Cache::NullStore.new

    assert LiveUpdateGate.new(:new_issues, 1).within_limit?(1)
    assert LiveUpdateGate.new(:new_issues, 1).within_limit?(1)
  end
end
