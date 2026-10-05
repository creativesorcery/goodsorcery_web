require "test_helper"
require Rails.root.join("test/test_helpers/live_cache_test_helper")

class Project::BroadcastingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper, LiveCacheTestHelper

  setup { @project = projects(:storefront) }

  test "a change schedules one broadcast after the debounce window" do
    freeze_time do
      assert_enqueued_with job: BroadcastProjectChangesJob, args: [ @project ], at: 2.seconds.from_now do
        @project.broadcast_changes_later
      end
    end
  end

  test "changes within the window collapse into one broadcast" do
    assert_enqueued_jobs 1, only: BroadcastProjectChangesJob do
      10.times { @project.broadcast_changes_later }
    end
  end

  test "a change after the window schedules another broadcast" do
    assert_enqueued_jobs 2, only: BroadcastProjectChangesJob do
      @project.broadcast_changes_later
      travel 3.seconds
      @project.broadcast_changes_later
    end
  end

  test "the recent feed is debounced per account across projects" do
    freeze_time do
      assert_enqueued_jobs 1, only: BroadcastRecentIssuesJob do
        @project.broadcast_changes_later
        projects(:billing).broadcast_changes_later
        projects(:marketing).broadcast_changes_later
      end
      assert_enqueued_with job: BroadcastRecentIssuesJob, args: [ accounts(:acme) ], at: 2.seconds.from_now
    end
  end

  test "projects are debounced independently" do
    assert_enqueued_jobs 2, only: BroadcastProjectChangesJob do
      @project.broadcast_changes_later
      projects(:billing).broadcast_changes_later
    end
  end
end
