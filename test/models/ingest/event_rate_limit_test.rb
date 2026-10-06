require "test_helper"

class Ingest::EventRateLimitTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @credential = ApiKey.authenticate(FIXTURE_TOKENS[:storefront_production])
  end

  teardown { Rails.cache = @original_cache }

  def key_count = Rails.cache.read("rate-limit:api/v1/events:key:#{@credential.id}", raw: true).to_i
  def account_count = Rails.cache.read("rate-limit:api/v1/events:account:#{@credential.account_id}", raw: true).to_i

  test "admits events against the key and the account counters" do
    limit = Ingest::EventRateLimit.new(@credential)

    assert limit.admit?(1)
    assert limit.admit?(25)
    assert_equal [ 26, 26 ], [ key_count, account_count ]
  end

  test "rejects all or nothing when the account would go over" do
    Rails.cache.increment("rate-limit:api/v1/events:account:#{@credential.account_id}",
                          Ingest::Limits::RATE_PER_ACCOUNT - 10, expires_in: 1.minute)
    limit = Ingest::EventRateLimit.new(@credential)

    assert_not limit.admit?(11)
    assert_equal 0, key_count, "the key's share is given back"
    assert_equal Ingest::Limits::RATE_PER_ACCOUNT - 10, account_count
    assert limit.admit?(10)
    assert limit.exhausted?
  end

  test "is exhausted once the key has no room for one more event" do
    limit = Ingest::EventRateLimit.new(@credential)
    assert_not limit.exhausted?

    Rails.cache.increment("rate-limit:api/v1/events:key:#{@credential.id}", Ingest::Limits::RATE_PER_KEY, expires_in: 1.minute)
    assert limit.exhausted?
  end
end
