# A member's token for the MCP endpoint (docs/ARCHITECTURE.md §14.1, docs/MCP.md).
# It covers one account and acts as its user, with the scopes it was given:
# "read" always, plus optional "triage" and "request_data".
#
# Only a SHA-256 digest of the token is stored, as for ingest keys: tokens are
# 32 random bytes, so a plain digest needs no slow KDF and lookups stay O(1).
# The plaintext exists only on the instance that generated it (#token), for
# the create response; it never reaches the session, flash, cache or logs.
#
#   token = user.personal_access_tokens.create!(account:, name: "Laptop", scopes: %w[read triage])
#   token.token                                 # => "gs_pat_…" (this instance only)
#   PersonalAccessToken.authenticate(token.token) # => the token, while valid
class PersonalAccessToken < ApplicationRecord
  PREFIX = "gs_pat_".freeze
  MAX_TOKEN_LENGTH = 128
  SCOPES = %w[read triage request_data].freeze
  OPTIONAL_SCOPES = (SCOPES - %w[read]).freeze
  EXPIRY_CHOICES = { "30" => 30.days, "90" => 90.days, "365" => 365.days, "never" => nil }.freeze
  DEFAULT_EXPIRY = "90".freeze
  MAX_ACTIVE_PER_USER = 20
  USAGE_GAP = 5.minutes
  # Revoked and expired tokens stay listed (with their audit log) this long,
  # then goodsorcery:prune deletes them (Ingest::Retention).
  KEPT_AFTER_END = 90.days

  belongs_to :user
  belongs_to :account
  has_many :activities, class_name: "AccessTokenActivity", inverse_of: :personal_access_token # rows cascade

  attr_reader :token

  self.filter_attributes += %i[token_digest]

  normalizes :name, with: ->(name) { name.squish }
  normalizes :scopes, with: ->(scopes) { ([ "read" ] + Array(scopes).map(&:to_s)).uniq & SCOPES }

  validates :name, presence: true, length: { maximum: 60 }
  validate :user_is_member, on: :create
  validate :within_active_limit, on: :create

  before_validation :assign_token, on: :create

  scope :active, ->(now = Time.current) { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", now) }
  scope :ended, ->(now = Time.current) { where.not(revoked_at: nil).or(where(expires_at: ..now)) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  class << self
    # Ends every active token of that user, or only those for one account.
    def revoke_all(user_id:, account_id: nil, now: Time.current)
      tokens = active(now).where(user_id:)
      tokens = tokens.where(account_id:) if account_id
      tokens.update_all(revoked_at: now)
    end

    # The token, while it is unrevoked, unexpired and its user is still a
    # member of its account (checked here on every use, one query), else nil.
    def authenticate(token, now: Time.current)
      return if token.blank? || token.length > MAX_TOKEN_LENGTH || !token.start_with?(PREFIX)

      active(now).joins(member_join).includes(:user, :account).find_by(token_digest: digest(token))
    end

    def digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)

    def generate_token = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"

    # The expiry time for one of EXPIRY_CHOICES' keys (nil: never expires).
    def expiry_for(choice, now: Time.current)
      duration = EXPIRY_CHOICES.fetch(choice.to_s) { EXPIRY_CHOICES.fetch(DEFAULT_EXPIRY) }
      duration && now + duration
    end

    private
      def member_join
        "INNER JOIN memberships ON memberships.account_id = personal_access_tokens.account_id " \
          "AND memberships.user_id = personal_access_tokens.user_id"
      end
  end

  def scope?(scope) = scopes.include?(scope.to_s)

  def revoked? = revoked_at.present?

  def expired?(now = Time.current) = expires_at.present? && expires_at <= now

  def active?(now = Time.current) = !revoked? && !expired?(now)

  def revoke
    update!(revoked_at: Time.current) unless revoked?
    self
  end

  # "gs_pat_…a1b2", the only form shown after creation.
  def masked_token = "#{PREFIX}…#{token_last4}"

  # Touches last_used_at at most once per USAGE_GAP (one UPDATE, no callbacks).
  def record_usage(now: Time.current)
    return if last_used_at && last_used_at > now - USAGE_GAP

    self.class.where(id:).update_all(last_used_at: now)
  end

  private
    def assign_token
      @token = self.class.generate_token
      self.token_digest = self.class.digest(@token)
      self.token_last4 = @token.last(4)
    end

    def user_is_member
      errors.add(:account, "must be one you belong to") unless account&.accessible_by?(user)
    end

    def within_active_limit
      return unless user && user.personal_access_tokens.active.count >= MAX_ACTIVE_PER_USER

      errors.add(:base, "You can have at most #{MAX_ACTIVE_PER_USER} active tokens. Revoke one first.")
    end
end
