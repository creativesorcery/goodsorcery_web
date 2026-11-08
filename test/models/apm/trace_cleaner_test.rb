require "test_helper"

class Apm::TraceCleanerTest < ActiveSupport::TestCase
  include ApmFixtureClock

  setup { @cleaner = Apm::TraceCleaner.new }

  test "path drops a leading origin with credentials" do
    assert_equal "/v1/charges", @cleaner.path("https://user:s3cret@api.example.com/v1/charges?token=abc")
  end

  test "path drops a protocol-relative origin" do
    assert_equal "/x", @cleaner.path("//api.example.com/x#frag")
  end

  test "path becomes / when only an origin is left" do
    assert_equal "/", @cleaner.path("http://user:pw@example.com?q=1")
  end

  test "plain paths keep their shape without the query string" do
    assert_equal "/checkout", @cleaner.path("/checkout?card=4242")
  end

  test "non-strings give nil" do
    assert_nil @cleaner.path(nil)
  end
end
