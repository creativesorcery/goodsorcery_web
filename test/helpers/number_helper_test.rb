require "test_helper"

class NumberHelperTest < ActionView::TestCase
  include NumberHelper

  test "delimited" do
    assert_equal "1,284", delimited(1284)
    assert_equal "0", delimited(nil)
  end

  test "compact_count" do
    assert_equal "0", compact_count(nil)
    assert_equal "950", compact_count(950)
    assert_equal "1k", compact_count(1_000)
    assert_equal "1.2k", compact_count(1_249)
    assert_equal "12k", compact_count(12_900)
    assert_equal "412k", compact_count(412_345)
    assert_equal "1M", compact_count(1_000_000)
    assert_equal "1.2M", compact_count(1_200_000)
    assert_equal "3B", compact_count(3_000_000_000)
  end
end
