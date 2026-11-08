require "test_helper"

class SetupProgressTest < ActiveSupport::TestCase
  test "a listening project is on step two of three" do
    progress = SetupProgress.new(projects(:marketing))

    assert_not progress.connected?
    assert_equal %i[done current pending], progress.steps.map(&:state)
    assert_equal 2, progress.current_step.number
    assert_equal "Step 2 of 3", progress.eyebrow
  end

  test "steps are numbered and labelled" do
    steps = SetupProgress.new(projects(:marketing)).steps

    assert_equal [ 1, 2, 3 ], steps.map(&:number)
    assert_equal [ "Create project", "Install the gem", "Receive first event" ], steps.map(&:label)
  end

  test "a rust app installs the crate" do
    projects(:marketing).platform = "rust"

    assert_equal "Install the crate", SetupProgress.new(projects(:marketing)).steps.second.label
  end

  test "a project with a first event is connected and every step is done" do
    progress = SetupProgress.new(projects(:storefront))

    assert_predicate progress, :connected?
    assert progress.steps.all?(&:done?)
    assert_nil progress.current_step
    assert_equal "Connected", progress.eyebrow
  end
end
