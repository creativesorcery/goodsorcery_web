require "test_helper"

class SignupTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  # Fixture accounts exist, so sign-up is closed unless kept open.
  setup { ENV["GOODSORCERY_ENABLE_SIGNUPS"] = "1" }
  teardown { ENV.delete("GOODSORCERY_ENABLE_SIGNUPS") }

  def signup(**overrides)
    Signup.new({ account_name: "Initech", name: "Peter Gibbons", email_address: "peter@initech.test",
                 password: "tps-reports-1", time_zone: "America/Chicago" }.merge(overrides))
  end

  test "creates the account, the user and an owner membership" do
    user = signup.save

    assert_kind_of User, user
    assert user.persisted?
    assert_equal "Initech", user.default_account.name
    assert user.memberships.sole.owner?
  end

  test "a later sign-up starts unverified and is sent a confirmation email" do
    user = nil
    assert_enqueued_emails 1 do
      user = signup.save
    end

    assert_not user.email_verified?
    assert_enqueued_email_with EmailVerificationsMailer, :verify, args: [ user ]
  end

  test "the first account's owner starts verified and gets no email" do
    form = signup
    form.define_singleton_method(:first_account?) { true }
    user = form.save

    assert user.email_verified?
    assert_enqueued_emails 0
  end

  test "returns false with errors when fields are missing" do
    form = signup(account_name: "", password: "")

    assert_equal false, form.save
    assert form.errors.added?(:account_name, :blank)
    assert form.errors.added?(:password, :blank)
  end

  test "rolls everything back when the user is invalid" do
    form = signup(email_address: users(:alex).email_address)

    assert_no_difference -> { Account.count } do
      assert_equal false, form.save
    end
    assert form.errors.of_kind?(:email_address, :taken)
  end

  test "maps account name errors to account_name" do
    form = signup(account_name: "x" * 81)

    assert_equal false, form.save
    assert form.errors.of_kind?(:account_name, :too_long)
  end

  test "takes the sign-up advisory lock inside the transaction, before the first-account check" do
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { signup.save }

    lock = statements.index { it.include?("pg_advisory_xact_lock(#{Signup::SIGN_UP_LOCK}, 0)") }
    assert lock, "expected the sign-up lock"
    assert_operator lock, :<, statements.index { it.match?(/SELECT 1 AS one FROM "accounts"/) }
    assert_operator lock, :<, statements.index { it.match?(/INSERT INTO "accounts"/) }
  end

  test "re-checks that sign-up is open under the lock, so the loser of a first-sign-up race is refused" do
    ENV.delete("GOODSORCERY_ENABLE_SIGNUPS") # an account now exists, so sign-up has closed
    form = signup

    assert_no_difference %w[Account.count User.count] do
      assert_equal false, form.save
    end
    assert_includes form.errors[:base], Signup::CLOSED_MESSAGE
    assert_enqueued_emails 0
  end

  test "save_owner creates a verified owner even while sign-up is closed, without mail" do
    ENV["GOODSORCERY_DISABLE_SIGNUPS"] = "1"
    form = signup

    user = form.save_owner
    assert user.persisted?
    assert user.email_verified?
    assert_not user.staff?
    assert user.memberships.sole.owner?
    assert_equal "Initech", form.account.name
    assert_enqueued_emails 0
  ensure
    ENV.delete("GOODSORCERY_DISABLE_SIGNUPS")
  end

  test "save_owner can also make the owner staff" do
    assert signup.save_owner(staff: true).staff?
  end

  test "save_owner refuses an email address that is already taken" do
    form = signup(email_address: " #{users(:alex).email_address.upcase} ")

    assert_no_difference %w[Account.count User.count] do
      assert_equal false, form.save_owner
    end
    assert form.errors.of_kind?(:email_address, :taken)
  end
end
