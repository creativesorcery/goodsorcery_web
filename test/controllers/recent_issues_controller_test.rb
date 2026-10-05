require "test_helper"

class RecentIssuesControllerTest < ActionDispatch::IntegrationTest
  test "renders the account feed frame without the layout" do
    sign_in_as users(:philip)

    get recent_issues_path

    assert_response :success
    assert_select "aside", count: 0
    assert_select "turbo-frame##{dom_id(accounts(:acme), :recent_issues)}[target=_top]" do
      assert_select "li", 4
      assert_select "li .coral-dot", 1
      assert_select "li .bg-lilac-400", 1
      assert_select "li .font-mono", text: "NoMethodError"
    end
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "shows resolutions with the resolver" do
    sign_in_as users(:philip)
    issues(:card_error).resolve(by: users(:jo))

    get recent_issues_path

    assert_select "li", text: /Resolved\s+Stripe::CardError in PaymentsController#confirm — by Jo M\./
    assert_select "li .bg-mint-400"
  end

  test "an outsider only sees their own account" do
    sign_in_as users(:outsider)

    get recent_issues_path

    assert_select "turbo-frame##{dom_id(accounts(:umbrella), :recent_issues)}"
    assert_select "turbo-frame##{dom_id(accounts(:acme), :recent_issues)}", count: 0
    assert_no_match "NoMethodError", response.body
    assert_match "RuntimeError", response.body
  end

  test "requires sign in" do
    get recent_issues_path

    assert_redirected_to new_session_path
  end
end
