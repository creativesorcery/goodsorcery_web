require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  include CableTestHelper

  setup { @user = users(:alex) }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create with an array of addresses sends no mail" do
    post passwords_path, params: { email_address: [ @user.email_address, "random-1@example.invalid" ] }

    assert_enqueued_emails 0
    assert_redirected_to new_session_path
  end

  test "edit" do
    get edit_password_path(token: @user.password_reset_token)
    assert_response :success
    assert_select "input[type=hidden][name=token]"
  end

  test "the reset token is filtered from the logged request path" do
    get edit_password_path(token: @user.password_reset_token)
    assert_equal "/password/edit?token=[FILTERED]", request.filtered_path
  end

  test "edit with invalid password reset token" do
    get edit_password_path(token: "invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "update" do
    @user.sessions.create!(account: accounts(:acme))

    assert_changes -> { @user.reload.password_digest } do
      put password_path, params: { token: @user.password_reset_token, password: "new-secret-9", password_confirmation: "new-secret-9" }
      assert_redirected_to new_session_path
    end
    assert_empty @user.sessions.reload

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update closes the live-update connections of every ended session" do
    sessions = [ sessions(:alex_browser), @user.sessions.create!(account: accounts(:acme)) ]
    others = users(:jo).sessions.create!(account: accounts(:acme))

    put password_path, params: { token: @user.password_reset_token, password: "new-secret-9", password_confirmation: "new-secret-9" }

    sessions.each { assert_cable_disconnected it }
    assert_cable_not_disconnected others
  end

  test "a completed reset lets that browser sign in although the address is locked out" do
    with_memory_cache do
      FailedSignIns::LIMIT.times { |n| post session_path, params: { email_address: @user.email_address, password: "wrong" }, env: { "REMOTE_ADDR" => "10.1.0.#{n}" } }
      post session_path, params: { email_address: @user.email_address, password: "password" }, env: { "REMOTE_ADDR" => "10.2.0.1" }
      assert_equal "Try again later.", flash[:alert], "locked out before the reset"

      put password_path, params: { token: @user.password_reset_token, password: "new-secret-9", password_confirmation: "new-secret-9" }
      post session_path, params: { email_address: @user.email_address, password: "new-secret-9" }, env: { "REMOTE_ADDR" => "10.2.0.1" }

      assert_redirected_to root_path
      assert cookies[:session_id].present?
    end
  end

  test "update confirms the email address, since the link reached the inbox" do
    @user.update!(email_verified_at: nil)
    put password_path, params: { token: @user.password_reset_token, password: "new-secret-9", password_confirmation: "new-secret-9" }

    assert @user.reload.email_verified?
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path, params: { token:, password: "new-secret-9", password_confirmation: "different-1" }
      assert_response :unprocessable_entity
    end

    assert_notice "match Password"
  end

  test "update with a too short password" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path, params: { token:, password: "short", password_confirmation: "short" }
    end

    assert_notice "too short"
  end

  test "reset requests are limited per email address across IPs" do
    with_memory_cache do
      5.times { |n| post passwords_path, params: { email_address: @user.email_address }, env: { "REMOTE_ADDR" => "10.0.0.#{n}" } }
      assert_enqueued_emails 5

      post passwords_path, params: { email_address: " #{@user.email_address.upcase}" }, env: { "REMOTE_ADDR" => "10.0.1.1" }
      assert_redirected_to new_session_path, "the same answer as a request that sent mail"
      assert_equal PasswordsController::RESET_NOTICE, flash[:notice]
      assert_nil flash[:alert]
      assert_enqueued_emails 5
      assert Rails.cache.instance_variable_get(:@data).keys.none? { it.include?("@") }, "no email address in cache keys"
    end
  end

  private
    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end

    def assert_notice(text)
      assert_match(/#{text}/, response.body)
    end
end
