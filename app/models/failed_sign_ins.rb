# Wrong-password sign-ins for one email address over the last WINDOW,
# against distributed credential stuffing (the per-IP limit can't see it).
# Only failures count, so signing in successfully never uses it up. The cache
# key is an HMAC of the address: no email address reaches the cache store.
#
#   failures = FailedSignIns.new("someone@example.com")
#   failures.record      # after a wrong password
#   failures.exceeded?   # => true from the LIMIT-th failure in the window
#   failures.digest      # the address's HMAC, also the remembered-browser marker
class FailedSignIns
  LIMIT = 20
  WINDOW = 1.hour

  attr_reader :digest

  def initialize(email_address)
    @digest = PrivateDigest.hexdigest("rate_limit.email", email_address.to_s.strip.downcase)
  end

  def record
    Ingest::RateLimitStore.increment(cache_key, 1, expires_in: WINDOW)
  end

  def exceeded?
    Ingest::RateLimitStore.read_counter(cache_key).to_i >= LIMIT
  end

  private
    def cache_key = "failed-sign-ins:#{digest}"
end
