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

  test "text scrubs a card the cut separates from the digits after it" do
    assert_equal "#{'m' * 83} [FILTERED]", @cleaner.text("#{'m' * 83} 41111111111111111225", 100)
  end

  test "non-strings give nil" do
    assert_nil @cleaner.path(nil)
  end

  test "null bytes are dropped, so Postgres can store the result" do
    assert_equal "app/controllers/checkouts_controller.rb", @cleaner.file("app/controllers/\u0000checkouts_controller.rb")
    assert_equal "/checkout", @cleaner.path("/check\u0000out")
    assert_equal "api.example.com", @cleaner.host("api.\u0000example.com")
  end

  test "null bytes are dropped before scrubbing, so one can't split a secret" do
    assert_equal "card [FILTERED]", @cleaner.text("card 41111111\u000011111111", 100)
  end
end
