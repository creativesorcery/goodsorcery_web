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
