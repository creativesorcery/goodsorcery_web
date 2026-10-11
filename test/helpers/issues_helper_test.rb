require "test_helper"

class IssuesHelperTest < ActionView::TestCase
  include ::NumberHelper, ChipHelper, EnvironmentsHelper

  test "issue_environment_chips shows three environments, then a count of the rest" do
    issue = Issue.new(environments: %w[production staging qa dev local])

    chips = issue_environment_chips(issue)

    assert_includes chips, %(<span class="chip chip-coral chip-sm">production</span>)
    assert_includes chips, %(<span class="chip chip-lilac chip-sm">qa</span>)
    assert_not_includes chips, ">dev<"
    assert_includes chips, %(<span class="chip chip-muted chip-sm">+2</span>)
    assert_nil issue_environment_chips(Issue.new(environments: []))
  end

  test "issue_summary_classes fades issues seen only outside production" do
    assert_equal "min-w-0", issue_summary_classes(Issue.new(environments: %w[production]))
    assert_equal "min-w-0 opacity-60", issue_summary_classes(Issue.new(environments: %w[staging]))
  end

  test "hourly histogram titles keep the minutes of half-hour zones" do
    travel_to Time.utc(2026, 10, 4, 9, 10) do
      Time.use_zone("Asia/Kolkata") do
        assert_equal [ "13:30 · 1 event", "14:30 · 2 events" ], send(:hourly_titles, [ 1, 2 ])
      end
    end
  end
end
