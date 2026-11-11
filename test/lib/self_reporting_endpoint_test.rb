require "test_helper"

class SelfReportingEndpointTest < ActiveSupport::TestCase
  test "GOODSORCERY_ENDPOINT always wins" do
    env = { "GOODSORCERY_ENDPOINT" => " https://errors.example.net ", "GOODSORCERY_PUBLIC_URL" => "https://errors.example.com" }

    assert_equal "https://errors.example.net", SelfReportingEndpoint.from_env(env, hosted: false)
    assert_equal "https://errors.example.net", SelfReportingEndpoint.from_env(env, hosted: true)
  end

  test "the hosted service reports to itself" do
    assert_equal "https://app.goodsorcery.com", SelfReportingEndpoint.from_env({ "GOODSORCERY_PUBLIC_URL" => "https://x.example" }, hosted: true)
    assert_equal "https://app.goodsorcery.com", SelfReportingEndpoint.from_env({}, hosted: true)
  end

  test "a self-hosted instance reports to its own public URL" do
    assert_equal "https://errors.example.com", SelfReportingEndpoint.from_env({ "GOODSORCERY_PUBLIC_URL" => "https://errors.example.com" }, hosted: false)
  end

  test "a self-hosted instance with no endpoint or public URL never defaults to the hosted service" do
    assert_nil SelfReportingEndpoint.from_env({}, hosted: false)
    assert_nil SelfReportingEndpoint.from_env({ "GOODSORCERY_ENDPOINT" => " ", "GOODSORCERY_PUBLIC_URL" => "" }, hosted: false)
  end
end
