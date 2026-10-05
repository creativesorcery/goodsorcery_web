# The test environment uses the null store; live-update debouncing needs a
# real store, so tests that exercise it swap in a fresh memory store.
module LiveCacheTestHelper
  extend ActiveSupport::Concern

  included do
    setup do
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown { Rails.cache = @original_cache }
  end
end
