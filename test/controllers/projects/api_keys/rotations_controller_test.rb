require "test_helper"

class Projects::ApiKeys::RotationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alex)
    @project = projects(:storefront)
    @api_key = api_keys(:storefront_production)
  end

  test "replaces the token and shows the new one in the row" do
    post project_api_key_rotation_path(@project, @api_key), as: :turbo_stream

    assert_response :success
    @api_key.reload
    assert_not_equal FIXTURE_TOKENS[:storefront_production], @api_key.token
    assert_match(/\Ags_live_/, @api_key.token)
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "turbo-stream[action=replace][target=?]", dom_id(@api_key) do
      assert_select "template code", @api_key.token
    end
    assert_not_includes response.body, FIXTURE_TOKENS[:storefront_production]
  end

  test "the old token stops working immediately, even when its lookup was cached" do
    old_token = FIXTURE_TOKENS[:storefront_production]

    with_memory_cache do
      assert ApiKey.authenticate(old_token), "precondition: the old token works and is cached"

      post project_api_key_rotation_path(@project, @api_key), as: :turbo_stream

      assert_nil ApiKey.authenticate(old_token)
      assert_equal @api_key.id, ApiKey.authenticate(@api_key.reload.token).id
    end
  end

  test "without turbo it redirects back to setup" do
    post project_api_key_rotation_path(@project, @api_key)

    assert_redirected_to project_setup_path(@project)
  end

  test "keys of another project are not found through this project" do
    post project_api_key_rotation_path(@project, api_keys(:marketing_production)), as: :turbo_stream

    assert_response :not_found
    assert_equal FIXTURE_TOKENS[:marketing_production], api_keys(:marketing_production).reload.token
  end

  test "outsiders get 404 and the key is untouched" do
    sign_in_as users(:outsider)

    post project_api_key_rotation_path(@project, @api_key), as: :turbo_stream

    assert_response :not_found
    assert_equal FIXTURE_TOKENS[:storefront_production], @api_key.reload.token
  end

  private
    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end
end
