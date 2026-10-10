# Sign-up form: creates an account, its first user and an owner membership in
# one transaction.
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes

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
    return false unless valid?

    ActiveRecord::Base.transaction { create_records }
    user.send_email_verification unless user.email_verified?
    user
  rescue ActiveRecord::RecordInvalid => invalid
    adopt_errors(invalid.record)
    false
  end

  private
    # The first account's owner is the person installing the instance, so they
    # start verified: a self-hosted instance may not have mail set up yet.
    def create_records
      verified_at = Time.current if first_account?
      @account = Account.create!(name: account_name)
      @user = User.create!(name:, email_address:, password:, time_zone:, email_verified_at: verified_at)
      account.memberships.create!(user:, role: :owner)
    end

    def first_account?
      !Account.exists?
    end

    def adopt_errors(record)
      prefix_account = record.is_a?(Account)
      record.errors.each do |error|
        errors.import(error, attribute: prefix_account ? :"account_#{error.attribute}" : error.attribute)
      end
    end
end
