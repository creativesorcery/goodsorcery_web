require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include CableTestHelper

  setup { @user = users(:alex) }

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

  test "after too many failed sign-ins for an address, a new browser is refused even with the right password" do
    with_memory_cache do
      fail_sign_ins(FailedSignIns::LIMIT)

      post session_path, params: { email_address: @user.email_address, password: "password" }, env: { "REMOTE_ADDR" => "10.2.0.1" }
      assert_redirected_to new_session_path
      assert_equal "Try again later.", flash[:alert]
      assert_nil cookies[:session_id]
    end
  end

  test "a browser that signed in to the address before is never locked out by other IPs' failures" do
    with_memory_cache do
      sign_in_with_password
      delete session_path
      fail_sign_ins(FailedSignIns::LIMIT + 5)

      sign_in_with_password(ip: "10.2.0.1")
      assert_redirected_to root_path
      assert cookies[:session_id].present?
    end
  end

  test "only failures count: successful sign-ins never use up the address's allowance" do
    with_memory_cache do
      FailedSignIns::LIMIT.times { |n| sign_in_with_password(ip: "10.3.0.#{n}") }
      cookies.delete(:known_sign_ins)
      fail_sign_ins(FailedSignIns::LIMIT - 1)

      sign_in_with_password(ip: "10.2.0.1")
      assert_redirected_to root_path
    end
  end

  test "the failure counter and the remembered-browser cookie hold no email address" do
    with_memory_cache do
      fail_sign_ins(1)
      sign_in_with_password

      assert Rails.cache.instance_variable_get(:@data).keys.none? { it.include?("@") }, "no email address in cache keys"
      assert cookies[:known_sign_ins].present?
      assert_not_includes cookies[:known_sign_ins], "alex"
    end
  end

  test "signing in starts a fresh Rails session but keeps the page to return to" do
    get projects_path
    assert_redirected_to new_session_path
    session_before = session.id.to_s
    assert session_before.present?

    sign_in_with_password
    assert_redirected_to projects_url
    assert_not_equal session_before, session.id.to_s
  end

  test "signing out resets the Rails session and closes only that browser's live-update connection" do
    get projects_path # leaves a return-to page in the Rails session
    session_before = session.id.to_s
    sign_in_as @user
    other_browser = @user.sessions.create!(account: accounts(:acme))
    signed_out = Current.session

    delete session_path

    assert_not_equal session_before, session.id.to_s
    assert_nil session[:return_to_after_authenticating]
    assert_not Session.exists?(signed_out.id)
    assert_cable_disconnected signed_out
    assert_cable_not_disconnected other_browser
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

    assert_no_match(/alex@example\.com/, output)
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
    def sign_in_with_password(ip: "127.0.0.1")
      post session_path, params: { email_address: @user.email_address, password: "password" }, env: { "REMOTE_ADDR" => ip }
    end

    # Spread over IPs, so the per-IP limit never kicks in.
    def fail_sign_ins(count)
      count.times do |n|
        post session_path, params: { email_address: " #{@user.email_address.upcase}", password: "wrong" }, env: { "REMOTE_ADDR" => "10.1.#{n / 200}.#{n % 200}" }
      end
    end

    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end

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
