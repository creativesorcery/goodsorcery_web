require "test_helper"

class IconHelperTest < ActionView::TestCase
  include IconHelper

  test "renders every icon as a decorative stroked svg" do
    IconHelper::ICONS.each_key do |name|
      svg = Nokogiri::XML(icon(name)).root

      assert_equal "svg", svg.name
      assert_equal "true", svg["aria-hidden"]
      assert svg.children.any?, "#{name} has no shapes"
    end
  end

  test "accepts size classes and rejects unknown icons" do
    assert_includes icon(:search, classes: "w-4 h-4"), %(class="w-4 h-4 shrink-0")
    assert_raises(KeyError) { icon(:nope) }
  end
end
