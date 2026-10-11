require "test_helper"

class IssueTagsHelperTest < ActionView::TestCase
  include EnvironmentsHelper

  Key = IssueTagCount::TagDistribution::Key
  Value = IssueTagCount::TagDistribution::Value

  def key_with(*shares, distinct: shares.size)
    values = shares.each_with_index.map { |share, index| Value.new("v#{index}", (share * 100).to_i, share) }
    Key.new("coupon", distinct, 100, values, false)
  end

  test "a dominant value among several is suspicious" do
    assert suspicious_tag?(key_with(0.92, 0.08))
    assert_not suspicious_tag?(key_with(0.6, 0.4))
    assert_not suspicious_tag?(key_with(1.0, distinct: 1)), "a single value is not suspicious"
  end

  test "segments use the palette, then a paper remainder" do
    segments = tag_segments(key_with(0.5, 0.3, distinct: 4))

    assert_equal [ ChartHelper::IRIS, ChartHelper::IRIS_DEEP, ChartHelper::PAPER ], segments.map { it[:color] }
    assert_in_delta 0.2, segments.last[:share]
    assert_equal "50% v0", segments.first[:title]
  end

  test "the environment key draws each environment in its tone" do
    values = [ Value.new("staging", 60, 0.6), Value.new("production", 40, 0.4) ]
    key = Key.new("environment", 2, 100, values, false)

    assert_equal [ ChartHelper::LILAC, ChartHelper::CORAL ], tag_segments(key).map { it[:color] }
  end

  test "a suspicious key highlights only the dominant value" do
    assert_equal [ ChartHelper::CORAL, ChartHelper::PAPER ], tag_segments(key_with(0.9, 0.1)).map { it[:color] }
  end
end
