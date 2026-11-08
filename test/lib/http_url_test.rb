require "test_helper"

class HttpUrlTest < ActiveSupport::TestCase
  test "keeps http and https URLs, stripped" do
    assert_equal "https://example.com/terms", HttpUrl.parse("  https://example.com/terms \n")
    assert_equal "http://example.com/privacy?v=2", HttpUrl.parse("http://example.com/privacy?v=2")
    assert_equal "HTTPS://example.com/terms", HttpUrl.parse("HTTPS://example.com/terms")
  end

  test "blank is unset" do
    assert_nil HttpUrl.parse(nil)
    assert_nil HttpUrl.parse("")
    assert_nil HttpUrl.parse("   ")
  end

  test "ignores anything that isn't an absolute http(s) URL" do
    [ "javascript:alert(1)", "mailto:legal@example.com", "ftp://example.com/terms", "/terms",
      "example.com/terms", "https://", "https:///terms", "https://exa mple.com" ].each do |value|
      assert_nil HttpUrl.parse(value), value
    end
  end
end
