require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  test "authenticate returns ids and environment only" do
    credential = ApiKey.authenticate(FIXTURE_TOKENS[:storefront_production])

    assert_equal api_keys(:storefront_production).id, credential.id
    assert_equal projects(:storefront).id, credential.project_id
    assert_equal "production", credential.environment
    assert_equal %i[id project_id environment], credential.to_h.keys
  end

  test "authenticate rejects unknown, blank and oversized tokens" do
    assert_nil ApiKey.authenticate("gs_live_nope")
    assert_nil ApiKey.authenticate("")
    assert_nil ApiKey.authenticate(nil)
    assert_nil ApiKey.authenticate("x" * 200)
  end

  test "authenticate caches the lookup, including misses, without the token" do
    token = FIXTURE_TOKENS[:storefront_staging]
    ApiKey.authenticate(token)

    cached = Rails.cache.read(ApiKey.cache_key_for(ApiKey.digest(token)))
    assert_equal [ api_keys(:storefront_staging).id, projects(:storefront).id, "staging" ], cached
    assert_queries_count(0) { ApiKey.authenticate(token) }

    ApiKey.authenticate("gs_live_missing")
    assert_queries_count(0) { assert_nil ApiKey.authenticate("gs_live_missing") }
  end

  test "new keys get a typed token, digest, prefix and last4" do
    key = projects(:marketing).api_keys.create!(environment: "staging")

    assert_match(/\Ags_test_[1-9A-HJ-NP-Za-km-z]{32}\z/, key.token)
    assert_equal ApiKey.digest(key.token), key.token_digest
    assert_equal key.token.first(12), key.token_prefix
    assert_equal key.token.last(4), key.token_last4
    assert_match(/\Ags_live_/, projects(:billing).api_keys.create!(environment: "production").token)
  end

  test "environment format and uniqueness per project" do
    assert_not projects(:storefront).api_keys.new(environment: "production").valid?
    assert_not projects(:storefront).api_keys.new(environment: "-bad").valid?
    assert_not projects(:storefront).api_keys.new(environment: "a" * 33).valid?
    assert projects(:storefront).api_keys.new(environment: " Review_App-1 ").valid?
  end

  test "rotate replaces the token and evicts the cached credential" do
    key = api_keys(:storefront_production)
    old_token = FIXTURE_TOKENS[:storefront_production]
    assert ApiKey.authenticate(old_token)

    assert_same key, key.rotate

    assert_nil ApiKey.authenticate(old_token)
    assert_equal key.id, ApiKey.authenticate(key.reload.token).id
    assert_not_equal old_token, key.token
  end

  test "masked token" do
    key = api_keys(:storefront_production)
    assert_equal "gs_live_Stor••••••••••••0001", key.masked_token
  end

  test "record_usage writes at most once a minute" do
    key = api_keys(:storefront_staging)

    ApiKey.record_usage(key.id)
    first = key.reload.last_used_at
    assert first

    travel 10.seconds do
      assert_queries_count(0) { ApiKey.record_usage(key.id) }
    end
    assert_equal first, key.reload.last_used_at
  end

  test "the lowest-id key of a project is the default" do
    assert api_keys(:storefront_production).default? ^ api_keys(:storefront_staging).default?
    assert_equal projects(:storefront).api_keys.min_by(&:id), projects(:storefront).default_api_key
  end
end
