require "test_helper"

class EnvironmentsHelperTest < ActionView::TestCase
  include ChipHelper

  test "environment_chip picks the chip tone from the name" do
    assert_dom_equal %(<span class="chip chip-coral">production</span>), environment_chip("production")
    assert_dom_equal %(<span class="chip chip-lilac chip-sm">staging</span>), environment_chip("staging", small: true)
    assert_dom_equal %(<span class="chip chip-muted">Development</span>), environment_chip("Development")
    assert_dom_equal %(<span class="chip chip-iris">eu-west</span>), environment_chip("eu-west")
  end

  test "environment_chip escapes the name" do
    assert_includes environment_chip("<b>"), "&lt;b&gt;"
  end

  test "environment_dot, text, bar classes and chart colour follow the tone" do
    assert_includes environment_dot("live"), "bg-coral-500"
    assert_includes environment_dot("qa"), "bg-lilac-400"
    assert_dom_equal %(<span class="text-ink-400">local</span>), environment_text("local")
    assert_includes environment_bar_classes("uat"), "bg-lilac-400/10"
    assert_includes environment_bar_classes("canary"), "bg-iris-500/10"
    assert_equal ChartHelper::CORAL, environment_color("prod")
    assert_equal ChartHelper::LILAC, environment_color("preview")
    assert_equal ChartHelper::PAPER, environment_color("test")
    assert_equal ChartHelper::IRIS, environment_color("eu-west")
  end

  test "every tone has a text, dot, bar and chart style" do
    EnvironmentTone::TONES.each do |tone|
      [ TEXT_TONES, DOT_TONES, BAR_TONES, CHART_COLORS ].each { |styles| assert styles.key?(tone), tone }
      assert ChipHelper::CHIP_TONES.key?(tone), tone
    end
  end
end
