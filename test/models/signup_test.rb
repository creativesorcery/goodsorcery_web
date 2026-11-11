require "test_helper"

class SignupTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

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
end
