require "test_helper"

class UptimeUrlTest < ActiveSupport::TestCase
  test "parses and normalises http and https URLs" do
    uri = UptimeUrl.parse("  HTTPS://Status.Example.com/up?x=1#section ")

    assert_equal "https://status.example.com/up?x=1", uri.to_s
    assert_equal "https://example.com/", UptimeUrl.parse("https://example.com").to_s
    assert_equal "http://example.com:8080/health", UptimeUrl.parse("http://example.com:8080/health").to_s
  end

  test "rejects other schemes, missing hosts, userinfo, junk and overlong URLs" do
    [ "", "   ", "ftp://example.com/", "javascript:alert(1)", "file:///etc/passwd", "gopher://example.com/",
      "https://", "/relative/path", "example.com", "https://user:pass@example.com/", "https://exa mple.com/",
      "https://example.com/#{'a' * UptimeUrl::MAX_LENGTH}", nil ].each do |input|
      assert_nil UptimeUrl.parse(input), input.inspect
    end
  end

  test "public? refuses localhost and blocked IP literals" do
    %w[http://localhost/ http://api.localhost:3000/ http://127.0.0.1/ http://[::1]/ http://169.254.169.254/
       http://10.0.0.1/ http://[fd00:ec2::254]/ http://0.0.0.0/].each do |input|
      assert_not UptimeUrl.new(input).public?, input
    end

    assert UptimeUrl.new("https://example.com/up").public?
    assert UptimeUrl.new("http://8.8.8.8/").public?
  end

  test "host is the lowercased host only" do
    assert_equal "status.example.com", UptimeUrl.new("https://Status.Example.com/up?token=secret").host
    assert_nil UptimeUrl.new("not a url").host
  end

  test "normalize keeps unparseable input stripped for validation" do
    assert_equal "https://example.com/", UptimeUrl.normalize(" https://example.com ")
    assert_equal "nope", UptimeUrl.normalize(" nope ")
  end
end
