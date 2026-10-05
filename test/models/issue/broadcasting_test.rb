require "test_helper"
require Rails.root.join("test/test_helpers/live_cache_test_helper")

class Issue::BroadcastingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper, LiveCacheTestHelper

  setup { @issue = issues(:nomethod) }

  test "a change schedules one broadcast after the debounce window" do
    freeze_time do
      assert_enqueued_with job: BroadcastIssueChangesJob, args: [ @issue ], at: 2.seconds.from_now do
        @issue.broadcast_changes_later
      end
    end
  end

  test "changes within the window collapse into one broadcast" do
    assert_enqueued_jobs 1, only: BroadcastIssueChangesJob do
      5.times { @issue.broadcast_changes_later }
    end
  end

  test "a change after the window schedules another broadcast" do
    assert_enqueued_jobs 2, only: BroadcastIssueChangesJob do
      @issue.broadcast_changes_later
      travel 3.seconds
      @issue.broadcast_changes_later
    end
  end

  test "each issue is debounced independently" do
    assert_enqueued_jobs 2, only: BroadcastIssueChangesJob do
      @issue.broadcast_changes_later
      issues(:regressed).broadcast_changes_later
      issues(:regressed).broadcast_changes_later
    end
  end

  test "a new issue is broadcast immediately, without a delay" do
    assert_enqueued_with job: BroadcastIssueChangesJob, args: [ @issue, { created: true } ], at: nil do
      @issue.broadcast_changes_later(created: true)
    end
  end

  test "creation broadcasts are not swallowed by the update debounce" do
    @issue.broadcast_changes_later

    assert_enqueued_with job: BroadcastIssueChangesJob, args: [ @issue, { created: true } ] do
      @issue.broadcast_changes_later(created: true)
    end
  end

  test "a storm of new issues is capped per project per window" do
    limit = Issue::Broadcasting::NEW_ROWS_PER_WINDOW

    assert_enqueued_jobs limit, only: BroadcastIssueChangesJob do
      (limit + 5).times { @issue.broadcast_changes_later(created: true) }
    end

    travel 3.seconds
    assert_enqueued_jobs 1, only: BroadcastIssueChangesJob do
      @issue.broadcast_changes_later(created: true)
    end
  end

  test "the new-issue cap is per project" do
    limit = Issue::Broadcasting::NEW_ROWS_PER_WINDOW
    limit.times { @issue.broadcast_changes_later(created: true) }

    assert_enqueued_jobs 1, only: BroadcastIssueChangesJob do
      issues(:billing_timeout).broadcast_changes_later(created: true)
    end
  end

  test "job arguments hold only the GlobalID" do
    @issue.broadcast_changes_later

    serialized = enqueued_jobs.last[:args].to_json
    assert_includes serialized, @issue.to_global_id.to_s
    [ @issue.message, @issue.exception_class, @issue.culprit ].each { |text| assert_not_includes serialized, text }
  end

  test "triage broadcasts the issue and its project" do
    assert_enqueued_jobs 1, only: BroadcastIssueChangesJob do
      assert_enqueued_jobs 1, only: BroadcastProjectChangesJob do
        @issue.resolve(by: users(:philip))
      end
    end
  end

  test "bulk triage broadcasts each changed issue once and the project once" do
    issues = projects(:storefront).issues.unresolved

    assert_enqueued_jobs issues.count, only: BroadcastIssueChangesJob do
      assert_enqueued_jobs 1, only: BroadcastProjectChangesJob do
        issues.resolve_all(by: users(:philip))
      end
    end
  end
end
