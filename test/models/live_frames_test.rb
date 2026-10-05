require "test_helper"

class LiveFramesTest < ActiveSupport::TestCase
  setup do
    @issue = issues(:nomethod)
    @project = @issue.project
    @frames = LiveFrames.new(@project, @issue)
  end

  test "stream names" do
    assert_equal [ accounts(:acme), :projects ], LiveFrames.projects_stream(accounts(:acme))
    assert_equal [ @project, :issues ], LiveFrames.issues_stream(@project)
    assert_equal [ @issue ], LiveFrames.issue_stream(@issue)
    assert_equal [ @project, :setup ], LiveFrames.setup_stream(@project)
  end

  test "issue frames point at the row, stats and chart endpoints" do
    assert_frame @frames.row, [ @project, :issues ], "row_issue_#{@issue.id}", "/projects/storefront/issues/GS-1042/row"
    assert_frame @frames.stats, [ @issue ], "stats_issue_#{@issue.id}", "/projects/storefront/issues/GS-1042/stats"
    assert_frame @frames.chart, [ @issue ], "chart_issue_#{@issue.id}", "/projects/storefront/issues/GS-1042/chart"
    assert_equal [ @frames.row, @frames.stats, @frames.chart ], @frames.issue_frames
  end

  test "project frames point at the summary, card, recent feed and listening endpoints" do
    frames = LiveFrames.new(@project)
    account = accounts(:acme)

    assert_frame frames.summary, [ @project, :issues ], "summary_project_#{@project.id}", "/projects/storefront/summary"
    assert_frame frames.card, [ account, :projects ], "card_project_#{@project.id}", "/projects/storefront/card"
    assert_frame frames.recent_issues, [ account, :projects ], "recent_issues_account_#{account.id}", "/recent_issues"
    assert_frame frames.listening, [ @project, :setup ], "listening_project_#{@project.id}", "/projects/storefront/listening"
    assert_equal 4, frames.project_frames.size
  end

  test "new issues are prepended into the project's container" do
    assert_equal "new_issues_project_#{@project.id}", @frames.new_issues_target
  end

  test "frame ids match the blueprint's dom_id conventions" do
    assert_equal ActionView::RecordIdentifier.dom_id(@issue, :row), @frames.row.target
    assert_equal ActionView::RecordIdentifier.dom_id(@project, :new_issues), @frames.new_issues_target
  end

  private
    def assert_frame(frame, streamables, target, src)
      assert_equal streamables, frame.streamables
      assert_equal target, frame.target
      assert_equal src, frame.src
    end
end
