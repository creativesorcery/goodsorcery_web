require "test_helper"

class BroadcastProjectChangesJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @project = projects(:storefront)
    @account = @project.account
  end

  test "reloads the issue list summary strip" do
    BroadcastProjectChangesJob.perform_now(@project)

    summary, = capture_turbo_stream_broadcasts([ @project, :issues ])
    assert_reload_frame summary, "summary_project_#{@project.id}", "/projects/storefront/summary"
  end

  test "reloads the overview card and the recent feed on the account stream" do
    BroadcastProjectChangesJob.perform_now(@project)

    card, recent = capture_turbo_stream_broadcasts([ @account, :projects ])
    assert_reload_frame card, "card_project_#{@project.id}", "/projects/storefront/card"
    assert_reload_frame recent, "recent_issues_account_#{@account.id}", "/recent_issues"
  end

  test "reloads the setup page listening panel" do
    project = projects(:marketing)

    BroadcastProjectChangesJob.perform_now(project)

    listening, = capture_turbo_stream_broadcasts([ project, :setup ])
    assert_reload_frame listening, "listening_project_#{project.id}", "/projects/marketing-site/listening"
  end

  test "sends nothing to other accounts' streams" do
    BroadcastProjectChangesJob.perform_now(@project)

    assert_no_turbo_stream_broadcasts [ accounts(:umbrella), :projects ]
  end

  test "broadcast payloads carry no captured error data" do
    BroadcastProjectChangesJob.perform_now(@project)

    payloads = [ [ @project, :issues ], [ @account, :projects ], [ @project, :setup ] ]
      .flat_map { |streamables| broadcasts(stream_name_from(streamables)) }
    assert_equal 4, payloads.size
    captured = @project.issues.pluck(:message, :exception_class, :culprit).flatten.compact_blank
    payloads.each do |payload|
      captured.each { |value| assert_not_includes payload, value }
    end
  end

  test "is discarded when the project no longer exists" do
    BroadcastProjectChangesJob.perform_later(@project)
    @project.delete

    assert_nothing_raised { perform_enqueued_jobs }
  end

  private
    def assert_reload_frame(element, target, src)
      assert_equal "reload_frame", element["action"]
      assert_equal target, element["target"]
      assert_equal src, element["src"]
      assert_empty element.at("template").inner_html
    end
end
