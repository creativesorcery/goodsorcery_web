require "test_helper"

class Mcp::CapturedTest < ActiveSupport::TestCase
  test "a value within every per-level cap is still bounded by its byte budget" do
    params = Array.new(30) { |index| [ "key#{index}", Array.new(30) { |inner| [ "k#{inner}", "x" * 300 ] }.to_h ] }.to_h
    assert_operator params.to_json.bytesize, :>, 250_000

    trimmed = Mcp::Captured.trim(params)

    assert_operator trimmed.to_json.bytesize, :<, Mcp::Captured::SECTION_BYTES + 1_000
    assert_match(/\A\d+ more keys\z/, trimmed[Mcp::Captured::CUT])
  end

  test "sections spend their parent's budget too" do
    budget = Mcp::OutputBudget.new(1_000)
    budget.section(800).string("a" * 2_000, 2_000)

    left = budget.remaining
    assert_operator left, :<, 200
    assert_equal left, budget.section(5_000).string("b" * 500, 500).count("b"), "a section never exceeds what its parent has left"
    assert_not budget.available?
  end

  test "small values come back whole" do
    value = { "coupon" => "FALL25", "items" => [ 1, 2 ], "nested" => { "ok" => true } }

    assert_equal value, Mcp::Captured.trim(value)
  end
end
