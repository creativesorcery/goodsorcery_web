require "test_helper"

class User::EmailVerificationTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:jo)
    @user.update!(email_verified_at: nil)
  end

  test "a verification token finds its user until it expires" do
    token = @user.email_verification_token

    assert_equal @user, User.find_by_email_verification_token(token)
    travel User::EmailVerification::EXPIRES_IN + 1.minute
    assert_nil User.find_by_email_verification_token(token)
  end

  test "changing the email address invalidates outstanding tokens" do
    token = @user.email_verification_token
    @user.update!(email_address: "jo.new@example.com")

    assert_nil User.find_by_email_verification_token(token)
  end

  test "garbage tokens find nothing" do
    assert_nil User.find_by_email_verification_token("nope")
    assert_nil User.find_by_email_verification_token(nil)
  end

  test "verify_email records the time once" do
    freeze_time
    @user.verify_email
    assert @user.reload.email_verified?
    assert_equal Time.current, @user.email_verified_at

    travel 1.day
    @user.verify_email
    assert_equal 1.day.ago, @user.reload.email_verified_at
  end

  test "send_email_verification enqueues the email" do
    assert_enqueued_email_with EmailVerificationsMailer, :verify, args: [ @user ] do
      @user.send_email_verification
    end
  end
end
