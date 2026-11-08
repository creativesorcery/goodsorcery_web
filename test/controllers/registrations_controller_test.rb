require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  VALID = {
    account_name: "Initech", name: "Peter Gibbons", email_address: "peter@initech.test",
    password: "tps-reports-1", time_zone: "America/Chicago"
  }.freeze

  setup { ENV["GOODSORCERY_ENABLE_SIGNUPS"] = "1" }
  teardown { ENV.delete("GOODSORCERY_ENABLE_SIGNUPS") }

  test "new" do
    get new_registration_path
    assert_response :success
  end

  test "new shows no agreement sentence without terms or privacy URLs" do
    with_legal_urls { get new_registration_path }

    assert_response :success
    assert_no_match "By signing up", response.body
    assert_select "form input[type=submit] ~ p", 0
  end

  test "new links the terms and privacy policy when both are set" do
    with_legal_urls(terms: "https://example.com/terms", privacy: "https://example.com/privacy") { get new_registration_path }

    assert_select "form p", text: "By signing up you agree to the Terms of Service and Privacy Policy." do
      assert_select "a[href=?][target=_top][rel=noopener]", "https://example.com/terms", text: "Terms of Service"
      assert_select "a[href=?][target=_top][rel=noopener]", "https://example.com/privacy", text: "Privacy Policy"
    end
  end

  test "new ignores a legal URL that is not http(s)" do
    # The same parsing config/application.rb applies to the env vars at boot.
    terms = HttpUrl.parse("javascript:alert(1)")
    with_legal_urls(terms:, privacy: HttpUrl.parse("https://example.com/privacy")) { get new_registration_path }

    assert_select "form p", text: "By signing up you agree to the Privacy Policy."
    assert_select "a[href^=javascript]", 0
    assert_no_match "Terms of Service", response.body
  end

  test "create makes an account, an owner and signs in" do
    assert_difference -> { Account.count } => 1, -> { User.count } => 1, -> { Membership.count } => 1 do
      post registration_path, params: { signup: VALID }
    end

    assert_redirected_to root_path
    assert cookies[:session_id]
    user = User.find_by!(email_address: "peter@initech.test")
    assert user.memberships.sole.owner?
    assert_equal "Initech", user.default_account.name
    assert_equal "America/Chicago", user.time_zone
    assert_not user.email_verified?
    assert_enqueued_email_with EmailVerificationsMailer, :verify, args: [ user ]
  end

  test "create with invalid data re-renders the form" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { signup: VALID.merge(email_address: users(:philip).email_address) }
    end

    assert_response :unprocessable_entity
    assert_equal 0, Account.where(name: "Initech").count
  end

  test "sign-ups can be disabled" do
    ENV["GOODSORCERY_DISABLE_SIGNUPS"] = "1"

    get new_registration_path
    assert_redirected_to new_session_path

    assert_no_difference -> { User.count } do
      post registration_path, params: { signup: VALID }
    end
  ensure
    ENV.delete("GOODSORCERY_DISABLE_SIGNUPS")
  end

  test "sign-ups are closed by default once an account exists" do
    ENV.delete("GOODSORCERY_ENABLE_SIGNUPS")

    get new_registration_path
    assert_redirected_to new_session_path
  end
end
