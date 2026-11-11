require "test_helper"

# The issues page's environment scope: the switch, the scope bar, the
# remembered choice per project, the project default, and the counts that
# follow it. storefront has production and staging keys; three unresolved
# issues are seen in production and one of them (regressed) in staging too.
class IssueListEnvironmentsTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  COOKIE = RemembersEnvironment::COOKIE.to_s

  setup do
    @project = projects(:storefront)
    sign_in_as users(:alex)
  end

  test "the switch reads All · production · staging, coloured, with All current by default" do
    get project_issues_path(@project)

    assert_select "nav.segmented[aria-label=Environment]" do
      assert_select "a", 3
      assert_select "a[aria-current=true][href=?]", project_issues_path(@project, q: "is:unresolved", env: ""), text: "All"
      assert_select "a[aria-current=false][href=?]", project_issues_path(@project, q: "is:unresolved env:production"), text: "production" do
        assert_select "span.bg-coral-500"
      end
      assert_select "a[aria-current=false][href=?]", project_issues_path(@project, q: "is:unresolved env:staging"), text: "staging" do
        assert_select "span.bg-lilac-400"
      end
    end
    assert_select "[aria-label='Environment scope']", count: 0
  end

  test "the switch keeps the other chips, text and sort" do
    get project_issues_path(@project, q: "is:unresolved level:error oops", sort: "events")

    assert_select "nav.segmented[aria-label=Environment] a[href=?]",
      project_issues_path(@project, q: "is:unresolved level:error env:staging oops", sort: "events"), text: "staging"
  end

  test "a non-production scope shows the scope bar with a way back to production" do
    get project_issues_path(@project, q: "is:unresolved env:staging")

    assert_select "[role=status][aria-label='Environment scope'].bg-lilac-400\\/10", text: /Viewing\s+staging/ do
      assert_select "a[href=?]", project_issues_path(@project, q: "is:unresolved env:production"), text: "Back to production"
    end
    assert_select "nav.segmented a[aria-current=true]", text: "staging"
    assert_select "form[role=search] .chip.chip-lilac", text: /env:staging/
  end

  test "without a production environment the scope bar offers all environments" do
    @project.api_keys.find_by!(environment: "production").destroy!

    get project_issues_path(@project, q: "env:staging")

    assert_select "[aria-label='Environment scope'] a[href=?]", project_issues_path(@project, q: "", env: ""), text: "Show all environments"
  end

  test "production scope shows no scope bar" do
    get project_issues_path(@project, q: "is:unresolved env:production")

    assert_select "[aria-label='Environment scope']", count: 0
  end

  test "the project default scopes the list, the summary, the tab counts and the sidebar badge" do
    @project.update!(default_environment: "staging")

    get project_issues_path(@project)

    assert_select "nav.segmented a[aria-current=true]", text: "staging"
    assert_select "[aria-label='Environment scope']", text: /Viewing\s+staging/
    assert_select "[id^=row_issue_]", 1
    assert_select "##{dom_id(issues(:regressed), :row)}"
    assert_select "turbo-frame##{dom_id(@project, :summary)}[src=?]", project_summary_path(@project, env: "staging")
    assert_select "h1", /— 1 unresolved/
    assert_select "nav[aria-label=Triage] a", text: /Unresolved\s*1/
    assert_select "nav[aria-label=Main] a[href=?]", project_issues_path(@project), text: /Issues\s*1/
  end

  test "tab counts follow the environment" do
    issues(:card_error).update_columns(environments: %w[staging])

    get project_issues_path(@project, q: "is:unresolved env:production")
    assert_select "nav[aria-label=Triage] a", text: /Unresolved\s*2/
    assert_select "nav[aria-label=Triage] a", text: /Assigned to me\s*1/

    get project_issues_path(@project, q: "is:unresolved env:staging")
    assert_select "nav[aria-label=Triage] a", text: /Unresolved\s*2/
    assert_select "nav[aria-label=Triage] a", text: /Assigned to me\s*0/

    get project_issues_path(@project, q: "is:unresolved", env: "")
    assert_select "nav[aria-label=Triage] a", text: /Unresolved\s*3/
  end

  test "an explicit choice is remembered for the project and wins over its default" do
    @project.update!(default_environment: "production")

    get project_issues_path(@project, q: "is:unresolved env:staging")
    assert_equal "staging", remembered_environment(@project)

    get project_issues_path(@project)
    assert_select "nav.segmented a[aria-current=true]", text: "staging"
    assert_select "[id^=row_issue_]", 1
  end

  test "choosing All is remembered too" do
    @project.update!(default_environment: "staging")

    get project_issues_path(@project, q: "is:unresolved", env: "")
    assert_equal "", remembered_environment(@project)

    get project_issues_path(@project)
    assert_select "nav.segmented a[aria-current=true]", text: "All"
    assert_select "[id^=row_issue_]", 3
  end

  test "a chip in the request wins over the remembered choice" do
    get project_issues_path(@project, q: "is:unresolved env:staging")

    get project_issues_path(@project, q: "is:unresolved env:production")

    assert_select "nav.segmented a[aria-current=true]", text: "production"
    assert_equal "production", remembered_environment(@project)
  end

  test "an unknown env: chip filters the list but is not remembered" do
    get project_issues_path(@project, q: "is:unresolved env:qa")

    assert_select "[id^=row_issue_]", 0
    assert_select "[aria-label='Environment scope']", text: /Viewing\s+qa/
    assert_nil remembered_environment(@project)
  end

  test "a remembered value that is not one of the project's environments is ignored" do
    @project.update!(default_environment: "staging")
    cookies[COOKIE] = signed_cookie(@project.id.to_s => "qa")

    get project_issues_path(@project)

    assert_select "nav.segmented a[aria-current=true]", text: "staging"
  end

  test "a tampered or unsigned cookie is ignored" do
    cookies[COOKIE] = { @project.id.to_s => "staging" }.to_json

    get project_issues_path(@project)

    assert_select "nav.segmented a[aria-current=true]", text: "All"
  end

  test "one project's remembered choice never applies to another" do
    marketing = projects(:marketing) # production only
    marketing.update!(default_environment: nil)
    get project_issues_path(@project, q: "is:unresolved env:production")
    assert_equal "production", remembered_environment(@project)

    get project_issues_path(marketing)
    assert_select "nav.segmented a[aria-current=true]", text: "All"
    assert_equal({ @project.id.to_s => "production" }, remembered_environments)
  end

  test "one cookie holds the choices, keeping only the most recently chosen projects" do
    stale = (1..RemembersEnvironment::REMEMBERED_PROJECTS).to_h { |n| [ "-#{n}", "production" ] }
    cookies[COOKIE] = signed_cookie(stale.merge(@project.id.to_s => "production"))

    get project_issues_path(@project, q: "is:unresolved env:staging")

    choices = remembered_environments
    assert_equal RemembersEnvironment::REMEMBERED_PROJECTS, choices.size
    assert_equal [ @project.id.to_s, "staging" ], choices.to_a.last
    assert_not choices.key?("-1")
    assert_nil cookies["issues_environment_#{@project.id}"]
  end

  test "a hover prefetch never changes the remembered choice" do
    get project_issues_path(@project, q: "is:unresolved env:production")

    get project_issues_path(@project, q: "is:unresolved env:staging"), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_equal "production", remembered_environment(@project)

    get project_issues_path(@project, env: ""), headers: { "Sec-Purpose" => "prefetch;prerender" }
    assert_equal "production", remembered_environment(@project)
  end

  test "links that change the list's scope are never prefetched on hover" do
    get project_issues_path(@project, q: "is:unresolved env:staging")

    assert_select "[data-turbo-prefetch=false]" do
      assert_select "form[role=search]"
      assert_select "nav.segmented[aria-label=Environment]"
      assert_select "nav[aria-label=Triage]"
    end
    assert_select "[aria-label='Environment scope'][data-turbo-prefetch=false]"
  end

  test "the sidebar badge follows the remembered choice on other pages" do
    get project_issues_path(@project, q: "is:unresolved env:staging")

    get edit_project_path(@project)

    assert_select "nav[aria-label=Main] a[href=?]", project_issues_path(@project), text: /Issues\s*1/
  end

  test "load more, the filter bar and the tabs keep an all-environments choice explicit" do
    @project.update!(default_environment: "production")

    get project_issues_path(@project, q: "is:unresolved", env: "")

    assert_select "form[role=search] input[type=hidden][name=env][value='']"
    assert_select "nav[aria-label=Triage] a[href=?]", project_issues_path(@project, q: "is:ignored", env: "")
  end

  test "an environment-scoped default view keeps the live prepend target for that environment" do
    @project.update!(default_environment: "production")

    get project_issues_path(@project)

    assert_select "##{dom_id(@project, :new_issues)}_production"
    assert_select "##{dom_id(@project, :new_issues)}", count: 0
  end

  test "an empty scoped default view is all clear for that environment" do
    @project.issues.update_all(environments: %w[production])

    get project_issues_path(@project, q: "is:unresolved env:staging")

    assert_select "h2", text: "✦ All clear"
    assert_select "p", text: "No unresolved staging issues in storefront."
  end

  test "an outsider gets 404 and no cookie, whatever the env param" do
    sign_in_as users(:outsider)

    get project_issues_path(@project, env: "staging")

    assert_response :not_found
    assert_nil cookies[COOKIE]
  end

  private
    def signed_cookie(value)
      jar = ActionDispatch::Request.new(Rails.application.env_config.deep_dup).cookie_jar
      jar.signed[COOKIE] = { value: }
      jar[COOKIE]
    end

    def remembered_environment(project)
      remembered_environments&.fetch(project.id.to_s, nil)
    end

    def remembered_environments
      return if cookies[COOKIE].blank?

      env = Rails.application.env_config.deep_dup.merge("HTTP_COOKIE" => "#{COOKIE}=#{CGI.escape(cookies[COOKIE])}")
      ActionDispatch::Request.new(env).cookie_jar.signed[COOKIE]
    end
end
