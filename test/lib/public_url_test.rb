require "test_helper"

class PublicUrlTest < ActiveSupport::TestCase
  test "is required in production-like boots" do
    assert_raises(PublicUrl::Missing) { PublicUrl.from_env({}, required: true) }
    assert_raises(PublicUrl::Missing) { PublicUrl.from_env({ "GOODSORCERY_PUBLIC_URL" => "errors.example.com" }, required: true) }
  end

  test "falls back to a localhost placeholder when not required (asset builds)" do
    assert_equal "localhost", PublicUrl.from_env({}, required: false).host
  end

  test "drives mailer link options and the allowed hosts" do
    url = PublicUrl.from_env({ "GOODSORCERY_PUBLIC_URL" => "https://errors.example.com/",
                               "GOODSORCERY_EXTRA_HOSTS" => "errors.internal, , 10.0.0.5" }, required: true)

    assert_equal({ host: "errors.example.com", protocol: "https" }, url.url_options)
    assert_equal [ "errors.example.com", "errors.internal", "10.0.0.5" ], url.allowed_hosts
    assert_equal "https://errors.example.com", url.to_s
  end

  test "keeps a non-standard port" do
    url = PublicUrl.new("http://errors.example.com:8080")
    assert_equal({ host: "errors.example.com", protocol: "http", port: 8080 }, url.url_options)
  end
end
