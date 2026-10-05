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
