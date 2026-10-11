require "test_helper"

class BroadcastIssueChangesJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @issue = issues(:nomethod)
    @project = @issue.project
  end

  test "leaves list rows to the project's batched rows reload" do
    BroadcastIssueChangesJob.perform_now(@issue)

    assert_no_turbo_stream_broadcasts [ @project, :issues ]
  end

  test "reloads the stat ribbon and chart on the issue stream" do
    BroadcastIssueChangesJob.perform_now(@issue)

    stats, chart = capture_turbo_stream_broadcasts([ @issue ])
    assert_reload_frame stats, "stats_issue_#{@issue.id}", "/projects/storefront/issues/GS-1042/stats"
    assert_reload_frame chart, "chart_issue_#{@issue.id}", "/projects/storefront/issues/GS-1042/chart"
  end

  test "a new issue is prepended as an empty row frame that fetches itself" do
    BroadcastIssueChangesJob.perform_now(@issue, created: true)

    prepend, production_prepend = capture_turbo_stream_broadcasts([ @project, :issues ])
    assert_equal "prepend", prepend["action"]
    assert_equal "new_issues_project_#{@project.id}", prepend["target"]
    assert_equal "new_issues_project_#{@project.id}_production", production_prepend["target"]
    assert_equal prepend.at("template").inner_html, production_prepend.at("template").inner_html

    frame = prepend.at("template").children.find(&:element?)
    assert_equal "turbo-frame", frame.name
    assert_equal "row_issue_#{@issue.id}", frame["id"]
    assert_equal "/projects/storefront/issues/GS-1042/row", frame["src"]
    assert_equal "_top", frame["target"]
    assert_empty frame.inner_html.strip
    assert_no_turbo_stream_broadcasts [ @issue ]
  end

  test "broadcast payloads carry no captured error data" do
    BroadcastIssueChangesJob.perform_now(@issue)
    BroadcastIssueChangesJob.perform_now(@issue, created: true)

    payloads = broadcasts(stream_name_from([ @project, :issues ])) + broadcasts(stream_name_from([ @issue ]))
    assert_equal 4, payloads.size, "stats and chart reloads, plus prepends into the all and production lists"
    payloads.each { |payload| assert_no_captured_data payload }
  end

  test "job arguments are a GlobalID and a flag only" do
    BroadcastIssueChangesJob.perform_later(@issue, created: true)

    serialized = enqueued_jobs.last[:args].to_json
    assert_includes serialized, @issue.to_global_id.to_s
    assert_no_captured_data serialized
  end

  test "is discarded when the issue no longer exists" do
    BroadcastIssueChangesJob.perform_later(@issue)
    @issue.delete

    assert_nothing_raised { perform_enqueued_jobs }
    assert_no_turbo_stream_broadcasts [ @project, :issues ]
  end

  private
    def assert_reload_frame(element, target, src)
      assert_equal "reload_frame", element["action"]
      assert_equal target, element["target"]
      assert_equal src, element["src"]
      assert_empty element.at("template").inner_html
    end

    def assert_no_captured_data(text)
      occurrence = occurrences(:nomethod_latest)
      sensitive = [ @issue.message, @issue.exception_class, @issue.culprit, @issue.transaction_name,
                    occurrence.exception_message, "mara@example.com", "FALL25", "price_cents" ]
      sensitive.compact_blank.each { |value| assert_not_includes text, value }
    end
end
