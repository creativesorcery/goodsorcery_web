require "test_helper"

class Projects::ApiKeys::RevealsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alex)
    @project = projects(:storefront)
    @api_key = api_keys(:storefront_production)
  end

  test "shows the full token in the token frame with copy and hide" do
    get project_api_key_reveal_path(@project, @api_key)

    assert_response :success
    assert_select "aside", count: 0
    assert_select "turbo-frame##{dom_id(@api_key, :token)}" do
      assert_select "code[data-clipboard-target=source]", FIXTURE_TOKENS[:storefront_production]
      assert_select "button[data-action='clipboard#copy']", "Copy"
      assert_select "a[href=?][data-turbo-frame=?]", project_api_key_path(@project, @api_key), dom_id(@api_key), text: "Hide"
    end
  end

  test "is never cached" do
    writes = []
    callback = ->(*, payload) { writes << payload[:key] }

    ActiveSupport::Notifications.subscribed(callback, /\Acache_write(_multi)?\.active_support\z/) do
      get project_api_key_reveal_path(@project, @api_key)
    end

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_empty writes
  end

  test "keys of another project in the account are not found through this project" do
    get project_api_key_reveal_path(@project, api_keys(:marketing_production))

    assert_response :not_found
  end

  test "outsiders get 404 and never see the token" do
    sign_in_as users(:outsider)

    get project_api_key_reveal_path(@project, @api_key)

    assert_response :not_found
    assert_not_includes response.body, FIXTURE_TOKENS[:storefront_production]
  end

  test "requires sign in" do
    sign_out

    get project_api_key_reveal_path(@project, @api_key)

    assert_redirected_to new_session_path
  end
end
