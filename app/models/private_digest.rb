# Keyed, namespaced HMAC-SHA256 for values that must be matched but never
# stored in plaintext (user identities, tag values).
#
# The key is derived from secret_key_base, so rotating secret_key_base breaks
# continuity with previously stored digests. That trade-off is accepted.
module PrivateDigest
  KEY_SALT = "goodsorcery private digest v1".freeze

  class << self
    def hexdigest(namespace, value)
      OpenSSL::HMAC.hexdigest("SHA256", key, "#{namespace}:#{value}")
    end

    def digest?(value)
      value.to_s.match?(/\A\h{64}\z/)
    end

    private
      def key
        @key ||= Rails.application.key_generator.generate_key(KEY_SALT, 32)
      end
  end
end
