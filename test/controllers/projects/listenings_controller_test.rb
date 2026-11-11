require "test_helper"

class Projects::ListeningsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alex)
  end

  test "a listening project keeps listening" do
    get project_listening_path(projects(:marketing))

    assert_response :success
    assert_select "aside", count: 0
    assert_select "turbo-frame##{dom_id(projects(:marketing), :listening)}", text: /Listening for your first event/
    assert_select "turbo-stream", count: 0
  end

  test "once connected it also refreshes the hero and stepper" do
    projects(:marketing).record_first_event(runtime_label: "Rails 8.1 · Ruby 4.0", at: Time.current)

    get project_listening_path(projects(:marketing))

    assert_select "turbo-frame##{dom_id(projects(:marketing), :listening)}" do
      assert_select "*", text: /First event received just now/
      assert_select "a[href=?]", project_issues_path(projects(:marketing))
      assert_select "turbo-stream[action=replace][target=?]", dom_id(projects(:marketing), :setup_hero)
    end
    assert_match "is connected", response.body
  end

  test "once connected it also fills the rail's MCP slot" do
    projects(:marketing).record_first_event(runtime_label: "Rails 8.1 · Ruby 4.0", at: Time.current)

    get project_listening_path(projects(:marketing))

    assert_select "turbo-frame##{dom_id(projects(:marketing), :listening)} turbo-stream[action=replace][target=?]",
      dom_id(projects(:marketing), :setup_mcp)
    stream = css_select("turbo-stream[target=#{dom_id(projects(:marketing), :setup_mcp)}] template").first
    assert_includes stream.inner_html, "Use it from your AI assistant"
    assert_includes stream.inner_html, %(href="#{access_tokens_path}")
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_listening_path(projects(:marketing))

    assert_response :not_found
  end
end
