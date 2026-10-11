# Proof that a user can read mail at their address. Sign-up sends a signed,
# expiring link; until it's clicked the user can sign in but can't create apps
# or API keys. Changing the address invalidates outstanding links, and a
# completed password reset counts as proof too.
module User::EmailVerification
  extend ActiveSupport::Concern

  EXPIRES_IN = 3.days

  # The token embeds what the block returns (signed, not encrypted), so it
  # carries a short keyed digest of the address rather than the address.
  included do
    scope :email_verified, -> { where.not(email_verified_at: nil) }

    generates_token_for(:email_verification, expires_in: EXPIRES_IN) do
      PrivateDigest.hexdigest("email_verification", email_address).first(16)
    end
  end

  class_methods do
    def find_by_email_verification_token(token)
      find_by_token_for(:email_verification, token)
    end
  end

  def email_verified?
    email_verified_at.present?
  end

  def verify_email
    update!(email_verified_at: Time.current) unless email_verified?
  end

  def email_verification_token
    generate_token_for(:email_verification)
  end

  def send_email_verification
    EmailVerificationsMailer.verify(self).deliver_later
  end
end
