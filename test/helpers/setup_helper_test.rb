require "test_helper"

class SetupHelperTest < ActionView::TestCase
  test "setup_step_heading puts the step number before the title" do
    assert_dom_equal %(<h2 class="font-display text-[20px] text-ink-50"><span class="text-iris-400 font-mono text-[14px] mr-2">ii.</span>Hook it in</h2>),
      setup_step_heading("ii.", "Hook it in")
  end

  test "setup_tab points at its panel and says whether it is selected" do
    assert_dom_equal %(<button type="button" class="tab" role="tab" aria-selected="true" aria-controls="install_manual" data-tabs-target="tab" data-action="tabs#select">Manual</button>),
      setup_tab("Manual", "install_manual", selected: true)
    assert_match 'aria-selected="false"', setup_tab("ENV only", "install_env")
  end

  test "setup_tab escapes its label" do
    assert_match "&lt;b&gt;", setup_tab("<b>", "panel")
  end
end
