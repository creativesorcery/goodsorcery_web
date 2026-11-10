class User < ApplicationRecord
  include EmailVerification, StaffSearchable

  SELF_DEMOTION = "You can't remove your own staff access. Ask another staff member to do it."

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy, inverse_of: :user
  has_many :accounts, through: :memberships
  has_many :alert_deliveries # rows cascade in the database
  has_many :personal_access_tokens # rows cascade in the database

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.squish }
  normalizes :time_zone, with: ->(tz) { ActiveSupport::TimeZone[tz.to_s] ? tz : "UTC" }

  validates :email_address, presence: true, uniqueness: true, length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 80 }
  validates :password, length: { minimum: 8 }, allow_nil: true

  staff_searchable_by :name, :email_address

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

  # Grants or removes access to the staff area. `by` is the staff member
  # making the change, who can't remove their own access (so the last staff
  # member can't lock everyone out by accident).
  def update_staff(staff, by:)
    staff = ActiveModel::Type::Boolean.new.cast(staff) || false
    return update(staff:) unless by == self && !staff

    errors.add(:base, SELF_DEMOTION)
    false
  end

  # For the List-Unsubscribe link of an alert ("alerts") or digest ("digest") email.
  def alert_mute_token(project, stream: "alerts")
    AlertMute.token_for(self, project, stream:)
  end
end
