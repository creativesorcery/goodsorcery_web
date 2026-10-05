require "test_helper"

class BroadcastRecentIssuesJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "reloads the account's recent feed by pointer" do
    account = accounts(:acme)
    BroadcastRecentIssuesJob.perform_now(account)

    recent, = capture_turbo_stream_broadcasts([ account, :projects ])
    assert_equal "reload_frame", recent["action"]
    assert_equal "recent_issues_account_#{account.id}", recent["target"]
    assert_equal "/recent_issues", recent["src"]
    assert_no_turbo_stream_broadcasts [ accounts(:umbrella), :projects ]
  end
end
