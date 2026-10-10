require "test_helper"

# Unverified users can sign in and browse, but can't create apps or API keys.
class VerifiedEmailRequiredTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:philip)
    @user.update!(email_verified_at: nil)
    sign_in_as @user
    @project = projects(:storefront)
  end

  test "the dashboard shows the confirm-your-email banner" do
    get projects_path
    assert_response :success
    assert_select "[role=status]", text: /We sent a link to #{Regexp.escape(@user.email_address)}/
    assert_select "form[action='#{email_verification_path}'] button", text: "Resend email"
  end

  test "verified users don't see the banner" do
    @user.verify_email
    get projects_path
    assert_select "form[action='#{email_verification_path}']", count: 0
  end

  test "adding an app is blocked" do
    get new_project_path
    assert_redirected_to root_path

    assert_no_difference -> { Project.count } do
      post projects_path, params: { project: { name: "Blocked" } }
    end
    assert_match "Confirm your email address first", flash[:alert]
  end

  test "creating and rotating API keys is blocked" do
    assert_no_difference -> { ApiKey.count } do
      post project_api_keys_path(@project), params: { api_key: { environment: "review" } }, as: :turbo_stream
    end
    assert_response :see_other

    api_key = api_keys(:storefront_production)
    assert_no_changes -> { api_key.reload.token_digest } do
      post project_api_key_rotation_path(@project, api_key), as: :turbo_stream
    end
  end

  test "browsing still works" do
    get project_setup_path(@project)
    assert_response :success
  end
end
