# Sign-up form: creates an account, its first user and an owner membership in
# one transaction. Also used by goodsorcery:create_owner (#save_owner).
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Namespace of the advisory lock that serialises sign-ups around the
  # first-account check (see #lock_sign_ups).
  SIGN_UP_LOCK = 4_713
  CLOSED_MESSAGE = "Sign-ups are closed.".freeze

  attribute :account_name, :string
  attribute :name, :string
  attribute :email_address, :string
  attribute :password, :string
  attribute :time_zone, :string, default: "UTC"

  validates :account_name, :name, :email_address, :password, presence: true

  attr_reader :user, :account

  # Closed by default once the first account exists, so an exposed
  # self-hosted instance does not take sign-ups from anyone on the internet.
  # GOODSORCERY_ENABLE_SIGNUPS=1 opens them (hosted service);
  # GOODSORCERY_DISABLE_SIGNUPS=1 closes them, even for the first account.
  def self.open?(env = ENV)
    return false if env["GOODSORCERY_DISABLE_SIGNUPS"] == "1"

    env["GOODSORCERY_ENABLE_SIGNUPS"] == "1" || !Account.exists?
  end

  # Returns the new user, or false with errors.
  def save
    return false unless valid? && create_records_while_open

    user.send_email_verification unless user.email_verified?
    user
  rescue ActiveRecord::RecordInvalid => invalid
    adopt_errors(invalid.record)
    false
  end

  # For the operator (goodsorcery:create_owner): an account and its verified
  # owner, whether or not public sign-up is open. Returns the user or false.
  def save_owner(staff: false)
    return false unless valid?

    ActiveRecord::Base.transaction { create_records(verified: true, staff:) }
    user
  rescue ActiveRecord::RecordInvalid => invalid
    adopt_errors(invalid.record)
    false
  end

  private
    # The first account's owner is the person installing the instance, so they
    # start verified: a self-hosted instance may not have mail set up yet.
    # The lock makes two concurrent sign-ups on a fresh instance take turns,
    # so only one of them can see "no account yet" and become that owner;
    # the other finds sign-up closed (unless it is kept open).
    def create_records_while_open
      ActiveRecord::Base.transaction do
        lock_sign_ups
        next closed unless ActiveRecord::Base.uncached { self.class.open? }

        create_records(verified: first_account?)
      end
    end

    def lock_sign_ups
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{SIGN_UP_LOCK}, 0)")
    end

    def create_records(verified:, staff: false)
      verified_at = Time.current if verified
      @account = Account.create!(name: account_name)
      @user = User.create!(name:, email_address:, password:, time_zone:, email_verified_at: verified_at, staff:)
      account.memberships.create!(user:, role: :owner)
    end

    def first_account?
      ActiveRecord::Base.uncached { !Account.exists? }
    end

    def closed
      errors.add(:base, CLOSED_MESSAGE)
      false
    end

    def adopt_errors(record)
      prefix_account = record.is_a?(Account)
      record.errors.each do |error|
        errors.import(error, attribute: prefix_account ? :"account_#{error.attribute}" : error.attribute)
      end
    end
end
