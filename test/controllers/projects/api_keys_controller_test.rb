require "test_helper"

class Projects::ApiKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alex)
    @project = projects(:storefront)
  end

  test "show renders the masked row frame" do
    api_key = api_keys(:storefront_production)

    get project_api_key_path(@project, api_key)

    assert_response :success
    assert_select "turbo-frame##{dom_id(api_key)}" do
      assert_select "turbo-frame##{dom_id(api_key, :token)} a", "Reveal"
    end
    assert_not_includes response.body, FIXTURE_TOKENS[:storefront_production]
  end

  test "show only finds keys of the given project" do
    get project_api_key_path(@project, api_keys(:marketing_production))

    assert_response :not_found
  end

  test "create appends a revealed key for a new environment" do
    assert_difference -> { @project.api_keys.count } do
      post project_api_keys_path(@project), params: { api_key: { environment: "Review" } }, as: :turbo_stream
    end

    api_key = @project.api_keys.last
    assert_equal "review", api_key.environment
    assert_equal users(:alex), api_key.created_by
    assert_match(/\Ags_test_/, api_key.token)
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "turbo-stream[action=append][target=?]", dom_id(@project, :api_keys) do
      assert_select "template code", api_key.token
    end
    assert_select "turbo-stream[action=replace][target=?]", dom_id(@project, :new_api_key)
  end

  test "create ignores attributes other than the environment" do
    post project_api_keys_path(@project), params: { api_key: { environment: "qa", token: "gs_live_chosen", project_id: projects(:umbrella_app).id } },
      as: :turbo_stream

    api_key = @project.api_keys.find_by!(environment: "qa")
    assert_not_equal "gs_live_chosen", api_key.token
  end

  test "create rejects a duplicate environment and reopens the form" do
    assert_no_difference -> { ApiKey.count } do
      post project_api_keys_path(@project), params: { api_key: { environment: "production" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target=?]", dom_id(@project, :new_api_key) do
      assert_select "template details[open]"
      assert_select "template [role=alert]", text: /Environment has already been taken/
    end
  end

  test "create without turbo redirects back to setup" do
    post project_api_keys_path(@project), params: { api_key: { environment: "preview" } }

    assert_redirected_to project_setup_path(@project)
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_api_key_path(@project, api_keys(:storefront_production))
    assert_response :not_found

    assert_no_difference -> { ApiKey.count } do
      post project_api_keys_path(@project), params: { api_key: { environment: "evil" } }, as: :turbo_stream
    end
    assert_response :not_found
  end
end
