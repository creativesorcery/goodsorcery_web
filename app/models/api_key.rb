# Ingest-only key, one per project environment. The token is stored encrypted
# (for Reveal) and as a SHA-256 digest (for O(1) lookup). Tokens are 32 random
# base58 characters, so a plain digest needs no slow KDF.
class ApiKey < ApplicationRecord
  Credential = Data.define(:id, :project_id, :environment)

  CACHE_TTL = 5.minutes
  MAX_TOKEN_LENGTH = 128
  ENVIRONMENT_FORMAT = /\A[a-z0-9][a-z0-9_-]{0,31}\z/

  belongs_to :project, inverse_of: :api_keys
  belongs_to :created_by, class_name: "User", optional: true

  encrypts :token

  normalizes :environment, with: ->(env) { env.strip.downcase }

  validates :environment, format: { with: ENVIRONMENT_FORMAT }, uniqueness: { scope: :project_id }

  before_validation :assign_token, on: :create

  class << self
    # Returns a Credential (ids and environment only) or nil. Cached, nil included.
    def authenticate(token)
      return if token.blank? || token.length > MAX_TOKEN_LENGTH

      row = Rails.cache.fetch(cache_key_for(digest(token)), expires_in: CACHE_TTL) do
        where(token_digest: digest(token)).pick(:id, :project_id, :environment)
      end
      Credential.new(*row) if row
    end

    # Touches last_used_at at most once a minute per key.
    def record_usage(id)
      return unless Rails.cache.write([ "api_key_used", id ], 1, unless_exist: true, expires_in: 1.minute)

      where(id:).update_all(last_used_at: Time.current)
    end

    def digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)

    def cache_key_for(digest) = [ "api_key", digest ]

    def generate_token(environment)
      "#{environment == "production" ? "gs_live_" : "gs_test_"}#{SecureRandom.base58(32)}"
    end
  end

  def rotate
    previous_digest = token_digest
    assign_token(force: true)
    save!
    Rails.cache.delete(self.class.cache_key_for(previous_digest))
    self
  end

  def masked_token
    "#{token_prefix}••••••••••••#{token_last4}"
  end

  def default?
    project.default_api_key == self
  end

  private
    def assign_token(force: false)
      return unless force || token.blank?

      self.token = self.class.generate_token(environment)
      self.token_digest = self.class.digest(token)
      self.token_prefix = token.first(12)
      self.token_last4 = token.last(4)
    end
end
