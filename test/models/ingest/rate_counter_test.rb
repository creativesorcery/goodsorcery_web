require "test_helper"

class Ingest::RateCounterTest < ActiveSupport::TestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  def count(key) = Rails.cache.read(key, raw: true).to_i

  test "takes amounts up to the limit and gives back a rejected amount" do
    counter = Ingest::RateCounter.new("key", 7, limit: 10)

    assert counter.take(4)
    assert counter.take(6)
    assert_not counter.take(1)
    assert_equal 10, count("rate-limit:api/v1/events:key:7"), "the rejected amount is given back"
  end

  test "a batch that would go over is rejected whole and leaves room for a smaller one" do
    counter = Ingest::RateCounter.new("key", 7, limit: 10)
    counter.take(8)

    assert_not counter.take(5)
    assert counter.take(2)
  end

  test "counts per window" do
    counter = Ingest::RateCounter.new("account", 3, limit: 2)
    assert counter.take(2)
    assert_not counter.take(1)

    travel 61.seconds do
      assert counter.take(2)
    end
  end

  test "never limits when the store keeps no counters" do
    Rails.cache = ActiveSupport::Cache::NullStore.new
    counter = Ingest::RateCounter.new("key", 7, limit: 1)

    assert counter.take(5)
    assert counter.take(5)
  end
end
