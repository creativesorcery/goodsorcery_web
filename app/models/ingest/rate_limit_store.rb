# Counter store for the ingest rate limits. It resolves Rails.cache on every
# request (Redis in production) instead of capturing the store at class load.
module Ingest::RateLimitStore
  def self.increment(...) = Rails.cache.increment(...)
end
