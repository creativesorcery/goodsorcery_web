require "test_helper"

class ShellTest < ActionDispatch::IntegrationTest
  test "sign-in page uses the auth layout and sends a strict CSP" do
    get new_session_path

    assert_response :success
    assert_select "title", "Sign in — Good Sorcery"
    assert_select ".panel form[action=?]", session_path
    assert_select "aside", count: 0
    assert_select "link[rel=stylesheet][href^=?]", "https://fonts.googleapis.com/css2"
    assert_strict_csp
  end

  test "auth pages have no inline styles or inline scripts" do
    [ new_session_path, new_password_path ].each do |path|
      get path

      assert_no_match(/style="/, response.body)
      assert_select "script:not([type=importmap]):not([type=module]):not([src])", count: 0
    end
  end

  test "signed-in dashboard renders the shell" do
    sign_in_as users(:philip)

    get root_path

    assert_response :success
    assert_select "aside a.nav-link[aria-current=page]", text: /Projects/
    assert_select "aside a[href=?]", project_issues_path(projects(:billing))
    assert_select "aside button", text: /Sign out/
    assert_select "header form[role=search][action=?] input[name=q]", search_path
    assert_strict_csp
  end

  test "signing out from the user menu" do
    sign_in_as users(:philip)

    delete session_path

    assert_redirected_to new_session_path
  end

  private
    def assert_strict_csp
      policy = response.headers["Content-Security-Policy"]

      assert_includes policy, "default-src 'self'"
      assert_includes policy, "frame-ancestors 'none'"
      assert_includes policy, "object-src 'none'"
      assert_match(/script-src 'self' 'nonce-[^']+'/, policy)
      assert_match(%r{style-src 'self' https://fonts.googleapis.com 'nonce-[^']+'}, policy)
      assert_includes policy, "font-src 'self' https://fonts.gstatic.com"
    end
end
