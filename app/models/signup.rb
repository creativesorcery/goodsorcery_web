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
    user
  rescue ActiveRecord::RecordInvalid => invalid
    adopt_errors(invalid.record)
    false
  end

  private
    def create_records
      @account = Account.create!(name: account_name)
      @user = User.create!(name:, email_address:, password:, time_zone:)
      account.memberships.create!(user:, role: :owner)
    end

    def adopt_errors(record)
      prefix_account = record.is_a?(Account)
      record.errors.each do |error|
        errors.import(error, attribute: prefix_account ? :"account_#{error.attribute}" : error.attribute)
      end
    end
end
