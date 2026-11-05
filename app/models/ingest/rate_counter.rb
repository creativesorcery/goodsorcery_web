# A fixed-window counter in Ingest::RateLimitStore that can advance by more
# than one, so a batch of N events uses N of the same allowance a single
# event uses 1 of. The key format matches Rails' rate_limit
# ("rate-limit:<scope>:<name>:<id>"). A store without counters (null store)
# never limits, like Rails' rate_limit. The performance endpoints count in
# their own scope (Apm::Limits::RATE_SCOPE), apart from the error counters.
class Ingest::RateCounter
  SCOPE = "api/v1/events".freeze

  attr_reader :limit

  def initialize(name, id, limit:, window: Ingest::Limits::RATE_WINDOW, scope: SCOPE)
    @key = [ "rate-limit", scope, name, id ].join(":")
    @limit = limit
    @window = window
  end

  # Takes amount from the allowance. Over the limit, it gives the amount back
  # (a rejected request uses up nothing) and returns false.
  def take(amount)
    count = Ingest::RateLimitStore.increment(@key, amount, expires_in: @window)
    return true if count.nil? || count <= limit

    give_back(amount)
    false
  end

  def give_back(amount)
    Ingest::RateLimitStore.decrement(@key, amount, expires_in: @window)
  end
end
