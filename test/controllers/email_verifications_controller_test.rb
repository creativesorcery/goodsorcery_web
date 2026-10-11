require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:jo)
    @user.update!(email_verified_at: nil)
  end

  test "show confirms the address and sends a signed-out user to sign in" do
    get email_verification_path(token: @user.email_verification_token)

    assert_redirected_to new_session_path
    assert_equal "Thanks, your email address is confirmed.", flash[:notice]
    assert @user.reload.email_verified?
  end

  test "show sends a signed-in user to the dashboard" do
    sign_in_as @user
    get email_verification_path(token: @user.email_verification_token)

    assert_redirected_to root_path
    assert @user.reload.email_verified?
  end

  test "show works in an old mobile browser (mail apps open links in any browser)" do
    get email_verification_path(token: @user.email_verification_token),
        headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) Version/16.6 Mobile/15E148 Safari/604.1" }

    assert_redirected_to new_session_path
    assert @user.reload.email_verified?
  end

  test "show rejects an invalid or expired token" do
    token = @user.email_verification_token
    travel User::EmailVerification::EXPIRES_IN + 1.minute

    get email_verification_path(token:)
    assert_redirected_to new_session_path
    assert_match "invalid or has expired", flash[:alert]

    get email_verification_path(token: "forged")
    assert_not @user.reload.email_verified?
  end

  test "create requires sign in" do
    post email_verification_path
    assert_redirected_to new_session_path
    assert_enqueued_emails 0
  end

  test "create resends the email to an unverified user" do
    sign_in_as @user

    assert_enqueued_email_with EmailVerificationsMailer, :verify, args: [ @user ] do
      post email_verification_path
    end
    assert_redirected_to root_path
  end

  test "create sends nothing once verified" do
    sign_in_as users(:philip)
    post email_verification_path
    assert_enqueued_emails 0
  end

  class RateLimitTest < ActionDispatch::IntegrationTest
    setup do
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      users(:jo).update!(email_verified_at: nil)
      sign_in_as users(:jo)
    end

    teardown { Rails.cache = @original_cache }

    test "resends are limited per user" do
      3.times { post email_verification_path }
      assert_enqueued_emails 3

      post email_verification_path
      assert_enqueued_emails 3
      assert_equal "Try again in a few minutes.", flash[:alert]
    end
  end
end
