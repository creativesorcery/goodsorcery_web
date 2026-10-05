require "test_helper"

class ChipHelperTest < ActionView::TestCase
  include ChipHelper

  FakeIssue = Data.define(:status, :fresh, :regressed_at) do
    def new? = fresh
    def regressed? = status == "unresolved" && regressed_at.present?
  end

  test "chip renders tone, dot, mono and small variants" do
    assert_dom_equal %(<span class="chip">production</span>), chip("production")
    assert_dom_equal %(<span class="chip chip-coral"><span class="coral-dot w-1.5 h-1.5"></span>Spiking</span>),
      chip("Spiking", tone: :coral, dot: true)
    assert_dom_equal %(<span class="chip chip-iris font-mono chip-sm">is:unresolved</span>),
      chip("is:unresolved", tone: :iris, mono: true, small: true)
  end

  test "chip escapes its text" do
    assert_includes chip("<script>"), "&lt;script&gt;"
  end

  test "issue_status_chip" do
    assert_includes issue_status_chip(FakeIssue.new("unresolved", true, nil)), "New · unresolved"
    assert_includes issue_status_chip(FakeIssue.new("unresolved", true, nil)), "coral-dot"
    assert_includes issue_status_chip(FakeIssue.new("unresolved", false, 1.hour.ago)), "chip-lilac"
    assert_includes issue_status_chip(FakeIssue.new("resolved", false, nil)), "chip-mint"
    assert_includes issue_status_chip(FakeIssue.new("ignored", false, nil)), "chip-muted"
    assert_dom_equal %(<span class="chip">Unresolved</span>), issue_status_chip(FakeIssue.new("unresolved", false, nil))
  end

  test "level_chip" do
    assert_dom_equal %(<span class="chip chip-coral font-mono">fatal</span>), level_chip("fatal")
    assert_dom_equal %(<span class="chip font-mono">error</span>), level_chip(:error)
    assert_includes level_chip("warning"), "chip-lilac"
  end
end
