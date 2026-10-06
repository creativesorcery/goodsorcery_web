# Counter store for the ingest rate limits. It resolves Rails.cache on every
# request (Redis in production) instead of capturing the store at class load.
module Ingest::RateLimitStore
  def self.increment(...) = Rails.cache.increment(...)
  def self.decrement(...) = Rails.cache.decrement(...)

  # Counters are written by increment, so they are read raw (Redis INCRBY values).
  def self.count(key) = Rails.cache.read(key, raw: true).to_i
end
