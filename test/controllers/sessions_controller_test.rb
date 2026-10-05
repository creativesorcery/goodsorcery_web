require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:philip) }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "pages are never cached by browsers or proxies" do
    get new_session_path
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "create with valid credentials starts a session in the default account" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
    assert_equal accounts(:acme), @user.sessions.order(:id).last.account
  end

  test "the session cookie expires with the session, not in 20 years" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    expires = response.headers["Set-Cookie"].to_s[/session_id=[^;]+;.*?expires=([^;]+)/i, 1]
    assert_in_delta Session::ABSOLUTE_LIFETIME.from_now, Time.httpdate(expires), 1.minute
  end

  test "sessions past their absolute lifetime or idle timeout are rejected" do
    sign_in_as @user
    get projects_path
    assert_response :success

    Current.session.update_columns(created_at: 31.days.ago)
    get projects_path
    assert_redirected_to new_session_path

    sign_in_as @user
    Current.session.update_columns(updated_at: 8.days.ago)
    get projects_path
    assert_redirected_to new_session_path
  end

  test "activity is recorded at most hourly" do
    sign_in_as @user
    Current.session.update_columns(updated_at: 2.hours.ago)
    get projects_path
    assert_in_delta Time.current, Current.session.reload.updated_at, 1.minute

    Current.session.update_columns(updated_at: 10.minutes.ago)
    assert_no_changes -> { Current.session.reload.updated_at } do
      get projects_path
    end
  end

  test "sign-in attempts are limited per email address across IPs" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    20.times { |n| post session_path, params: { email_address: @user.email_address, password: "wrong" }, env: { "REMOTE_ADDR" => "10.1.0.#{n}" } }

    post session_path, params: { email_address: @user.email_address, password: "password" }, env: { "REMOTE_ADDR" => "10.2.0.1" }
    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  ensure
    Rails.cache = original
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "create does not log the password or email" do
    output = capture_log do
      post session_path, params: { email_address: @user.email_address, password: "password" }
    end

    assert_no_match(/philip@example\.com/, output)
    assert_no_match(/"password"=>"password"|password: "password"/, output)
  end

  test "destroy" do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "unauthenticated visitors are sent to sign in" do
    delete session_path
    assert_redirected_to new_session_path
  end

  private
    def capture_log
      io = StringIO.new
      original = Rails.logger
      ActionController::Base.logger = Rails.logger = ActiveSupport::Logger.new(io).tap { |l| l.level = :debug }
      yield
      io.string
    ensure
      ActionController::Base.logger = Rails.logger = original
    end
end
