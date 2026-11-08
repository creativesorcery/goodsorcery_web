require "test_helper"

class Api::V1::VerificationsControllerTest < ActionDispatch::IntegrationTest
  def verify(token = FIXTURE_TOKENS[:storefront_staging])
    get api_v1_verification_path, headers: token ? { "Authorization" => "Bearer #{token}" } : {}
  end

  test "200 with the key's environment, creating nothing" do
    assert_no_difference(-> { InboundEvent.count }) { verify }

    assert_response :ok
    assert_equal({ "ok" => true, "environment" => "staging" }, response.parsed_body)
    assert_not_includes response.body, FIXTURE_TOKENS[:storefront_staging]
  end

  test "401 for missing, unknown or rotated keys" do
    api_keys(:storefront_staging).rotate
    [ nil, "gs_live_unknown", FIXTURE_TOKENS[:storefront_staging] ].each do |token|
      verify token
      assert_response :unauthorized
      assert_equal({ "error" => "invalid_api_key" }, response.parsed_body)
      assert_equal 'Bearer realm="ingest"', response.headers["WWW-Authenticate"]
    end
  end

  test "does not count toward the monthly quota" do
    accounts(:acme).update_entitlements!("monthly_event_quota" => 1)
    with_hosted_mode { verify }
    assert_response :ok
  end

  class RateLimitTest < ActionDispatch::IntegrationTest
    setup do
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown { Rails.cache = @original_cache }

    def verify(token = FIXTURE_TOKENS[:storefront_production])
      get api_v1_verification_path, headers: { "Authorization" => "Bearer #{token}" }
    end

    test "allows a modest number of checks per key, then 429 with Retry-After" do
      Ingest::Limits::VERIFY_RATE_PER_KEY.times { verify }
      assert_response :ok

      verify
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
      assert_equal({ "error" => "rate_limited" }, response.parsed_body)

      verify FIXTURE_TOKENS[:storefront_staging]
      assert_response :ok, "other keys are unaffected"
    end

    test "429 once an IP exceeds its limit, before authentication" do
      Rails.cache.increment("rate-limit:api/v1/verifications:ip:127.0.0.1", Ingest::Limits::RATE_PER_IP, expires_in: 1.minute)
      verify "gs_live_unknown"
      assert_response :too_many_requests
    end

    test "uses none of the ingest allowances" do
      verify
      key_id = api_keys(:storefront_production).id
      assert_nil Rails.cache.read("rate-limit:api/v1/events:key:#{key_id}", raw: true)
      assert_nil Rails.cache.read("rate-limit:api/v1/events:ip:127.0.0.1", raw: true)
    end
  end
end
