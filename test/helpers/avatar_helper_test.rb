require "test_helper"

class AvatarHelperTest < ActionView::TestCase
  include AvatarHelper

  TileProject = Data.define(:name, :color, :listening) do
    def listening? = listening
  end

  test "initials_avatar shows up to two initials with a stable tint" do
    avatar = initials_avatar("Philip Nguyen Jr", size: :lg)

    assert_includes avatar, ">PN<"
    assert_includes avatar, "w-8 h-8"
    assert_equal avatar, initials_avatar("Philip Nguyen Jr", size: :lg)
    assert_includes initials_avatar(""), ">?<"
    assert_includes initials_avatar("<b>"), "&lt;"
  end

  test "empty_avatar is a dashed circle" do
    assert_includes empty_avatar, "border-dashed"
  end

  test "project_tile tints by colour and outlines listening projects" do
    assert_includes project_tile(TileProject.new("storefront", "coral", false), size: :lg), "bg-coral-100"
    assert_includes project_tile(TileProject.new("storefront", "coral", false), size: :lg), ">S<"
    assert_includes project_tile(TileProject.new("marketing", "mint", true)), "border-dashed"
  end
end
