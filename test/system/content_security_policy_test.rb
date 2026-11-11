require "application_system_test_case"

# Every response carries a fresh CSP nonce (config/initializers/content_security_policy.rb).
# Turbo Drive keeps the first page's policy, so later visits must neither re-run the
# importmap scripts nor trip the policy.
class ContentSecurityPolicyTest < ApplicationSystemTestCase
  test "Turbo visits keep working without CSP violations although each response has a new nonce" do
    sign_in
    visit_connected projects_path
    page.execute_script("window.turboVisitMarker = true")
    first_nonce = csp_meta_nonce

    [ project_issues_path(projects(:storefront)), project_issues_path(projects(:billing)) ].each do |path|
      page.execute_script("document.querySelector(arguments[0]).click()", "a[href='#{path}']")
      assert_current_path path
    end

    assert page.evaluate_script("window.turboVisitMarker"), "navigation stayed a Turbo visit (no full reload)"
    assert_not_equal first_nonce, csp_meta_nonce
    assert_equal 1, page.evaluate_script("document.querySelectorAll('script[type=importmap]').length")
    assert_empty page.driver.browser.logs.get(:browser).map(&:message).grep(/Content Security Policy/)
  end

  private
    def csp_meta_nonce = page.evaluate_script("document.querySelector('meta[name=csp-nonce]').content")
end
