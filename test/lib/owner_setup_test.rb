require "test_helper"

class OwnerSetupTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  FakeConsole = Struct.new(:answers, :prompts) do
    def getpass(prompt)
      prompts << prompt
      answers.shift
    end
  end

  ENV_VALUES = { "EMAIL" => " Owner@Example.com ", "NAME" => "Alex Rivera", "ACCOUNT" => "Initech" }.freeze

  test "creates the account and its verified owner with the password from PASSWORD" do
    message = OwnerSetup.new(ENV_VALUES.merge("PASSWORD" => "tps-reports-1"), console: nil).create

    user = User.find_by!(email_address: "owner@example.com")
    assert_equal "Created owner@example.com, owner of Initech.", message
    assert user.email_verified?
    assert_not user.staff?
    assert_equal "Initech", user.memberships.sole.tap { assert it.owner? }.account.name
    assert User.authenticate_by(email_address: "owner@example.com", password: "tps-reports-1")
    assert_enqueued_emails 0
  end

  test "prompts twice on the terminal when PASSWORD is not set" do
    console = FakeConsole.new([ "tps-reports-1", "tps-reports-1" ], [])

    OwnerSetup.new(ENV_VALUES, console:).create

    assert_equal [ "Password: ", "Confirm password: " ], console.prompts
    assert User.authenticate_by(email_address: "owner@example.com", password: "tps-reports-1")
  end

  test "refuses mismatched passwords" do
    console = FakeConsole.new([ "tps-reports-1", "tps-reports-2" ], [])

    error = assert_raises(OwnerSetup::Failure) { OwnerSetup.new(ENV_VALUES, console:).create }
    assert_equal OwnerSetup::MISMATCH, error.message
    assert_not User.exists?(email_address: "owner@example.com")
  end

  test "asks for PASSWORD when there is no terminal" do
    error = assert_raises(OwnerSetup::Failure) { OwnerSetup.new(ENV_VALUES, console: nil).create }
    assert_equal OwnerSetup::NO_TERMINAL, error.message
  end

  test "STAFF=1 also makes the owner staff" do
    message = OwnerSetup.new(ENV_VALUES.merge("PASSWORD" => "tps-reports-1", "STAFF" => "1"), console: nil).create

    assert_equal "Created owner@example.com, owner of Initech (staff).", message
    assert User.find_by!(email_address: "owner@example.com").staff?
  end

  test "shows the usage, before prompting, when EMAIL, NAME or ACCOUNT is missing" do
    %w[EMAIL NAME ACCOUNT].each do |name|
      console = FakeConsole.new([], [])
      error = assert_raises(OwnerSetup::Failure) { OwnerSetup.new(ENV_VALUES.merge(name => " "), console:).create }

      assert_equal OwnerSetup::USAGE, error.message
      assert_empty console.prompts
    end
  end

  test "refuses an email address that already has a user" do
    assert_no_difference %w[Account.count User.count] do
      error = assert_raises(OwnerSetup::Failure) do
        OwnerSetup.new(ENV_VALUES.merge("EMAIL" => users(:alex).email_address, "PASSWORD" => "tps-reports-1"), console: nil).create
      end
      assert_equal "Could not create the owner: Email address has already been taken.", error.message
    end
  end

  test "reports invalid values, such as a short password" do
    error = assert_raises(OwnerSetup::Failure) { OwnerSetup.new(ENV_VALUES.merge("PASSWORD" => "short"), console: nil).create }
    assert_match(/Could not create the owner: Password is too short/, error.message)
  end
end
