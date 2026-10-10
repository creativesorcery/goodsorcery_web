class User < ApplicationRecord
  include EmailVerification

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy, inverse_of: :user
  has_many :accounts, through: :memberships

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.squish }
  normalizes :time_zone, with: ->(tz) { ActiveSupport::TimeZone[tz.to_s] ? tz : "UTC" }

  validates :email_address, presence: true, uniqueness: true, length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 80 }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # The account a new browser session works in: the earliest membership.
  def default_account
    accounts.order("memberships.created_at", "memberships.id").first
  end

  def initials
    name.to_s.split.first(2).map { |word| word[0] }.join.upcase
  end

  def first_name
    name.to_s.split.first
  end
end
