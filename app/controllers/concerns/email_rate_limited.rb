# Per-address throttling on top of the per-IP limits, against distributed
# credential stuffing and reset-mail floods. The counter is keyed by an HMAC
# of the address, so no email address reaches the cache store.
module EmailRateLimited
  extend ActiveSupport::Concern

  class_methods do
    def rate_limit_by_email(to:, within:, only:, &with)
      rate_limit to:, within:, only:, with:, name: "email", by: -> { email_rate_limit_key }, store: Ingest::RateLimitStore
    end
  end

  private
    def email_rate_limit_key
      PrivateDigest.hexdigest("rate_limit.email", params[:email_address].to_s.strip.downcase)
    end
end
