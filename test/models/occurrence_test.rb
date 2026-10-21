require "test_helper"

class OccurrenceTest < ActiveSupport::TestCase
  setup { @occurrence = occurrences(:nomethod_latest) }

  test "to_param is the uuid" do
    assert_equal "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1", @occurrence.to_param
  end

  test "latest and oldest within an issue" do
    assert_equal occurrences(:nomethod_latest), issues(:nomethod).occurrences.latest
    assert_equal occurrences(:nomethod_oldest), issues(:nomethod).occurrences.oldest
    assert_nil issues(:card_error).occurrences.latest
  end

  test "readers expose the normalised payload" do
    assert_match(/price_cents/, @occurrence.exception_message)
    assert_equal "app/services/cart_total.rb", @occurrence.frames.first["file"]
    assert_equal 7, @occurrence.frames.size
    assert_equal "POST", @occurrence.request["method"]
    assert_equal "[FILTERED]", @occurrence.params["card_token"]
    assert_equal "[FILTERED]", @occurrence.headers["Cookie"]
    assert_equal 5521, @occurrence.session_data["user_id"]
    assert_equal "mara", @occurrence.user["username"]
    assert_equal 4, @occurrence.breadcrumbs.size
    assert_equal "web-7f9c-2", @occurrence.context["host"]
    assert_equal "Mobile Safari", @occurrence.tags["browser"]
    assert_equal "CheckoutsController#create", @occurrence.transaction_name
  end

  test "readers default when the payload lacks sections or has the wrong types" do
    occurrence = Occurrence.new(payload: { exception: { backtrace: "nope" }, params: [ 1 ], breadcrumbs: { a: 1 } }.to_json)

    assert_equal "", occurrence.exception_message
    assert_equal [], occurrence.frames
    assert_equal({}, occurrence.params)
    assert_equal [], occurrence.breadcrumbs
    assert_equal({}, occurrence.user)
    assert_nil occurrence.transaction_name
  end

  test "malformed payload reads as empty" do
    assert_equal({}, Occurrence.new(payload: "not json").data)
    assert_equal({}, Occurrence.new(payload: "[1,2]").data)
  end

  test "data is memoized and reset on reload" do
    assert_same @occurrence.data, @occurrence.data
    first = @occurrence.data
    @occurrence.reload
    assert_not_same first, @occurrence.data
  end

  test "retention constants" do
    assert_equal 100, Occurrence::RETAINED_PER_ISSUE
    assert_equal 3_000, Occurrence::RETAINED_PER_PROJECT
  end
end
