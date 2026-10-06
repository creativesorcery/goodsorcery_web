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
    assert_not limit.admit?(1)
  end

  test "admitting nothing touches no counter" do
    Rails.cache.increment("rate-limit:api/v1/events:key:#{@credential.id}", Ingest::Limits::RATE_PER_KEY, expires_in: 1.minute)
    limit = Ingest::EventRateLimit.new(@credential)

    assert limit.admit?(0)
    assert_equal [ Ingest::Limits::RATE_PER_KEY, 0 ], [ key_count, account_count ]
  end

  test "gives back events taken earlier to both counters" do
    limit = Ingest::EventRateLimit.new(@credential)
    limit.admit?(3)
    limit.give_back(1)

    assert_equal [ 2, 2 ], [ key_count, account_count ]
  end
end
