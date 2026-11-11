require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alex)
  end

  test "requires authentication" do
    sign_out

    get search_path(q: "error")

    assert_redirected_to new_session_path
  end

  test "blank search shows a hint" do
    get search_path

    assert_response :success
    assert_select "h2", "Search projects and issues"
  end

  test "a short id jumps to the issue" do
    get search_path(q: "gs-1042")

    assert_redirected_to project_issue_path(projects(:storefront), issues(:nomethod))
  end

  test "a short id in another project of the account" do
    get search_path(q: "BA-7")

    assert_redirected_to project_issue_path(projects(:billing), issues(:billing_timeout))
  end

  test "a short id shared by two projects (legacy duplicate prefixes) lists both instead of guessing" do
    projects(:billing).update_column(:issue_prefix, "GS")
    issues(:billing_timeout).update_column(:number, 1042)

    get search_path(q: "GS-1042")

    assert_response :success
    assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:nomethod))
    assert_select "a[href=?]", project_issue_path(projects(:billing), issues(:billing_timeout))
  end

  test "a short id from another account does not jump" do
    get search_path(q: "UA-1")

    assert_response :success
    assert_no_match(/T-virus/, response.body)
  end

  test "free text finds issues across the account's projects and projects by name" do
    get search_path(q: "timeout")

    assert_response :success
    assert_select "a[href=?]", project_issue_path(projects(:billing), issues(:billing_timeout))
    assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:resolved_issue))

    get search_path(q: "billing")

    assert_select "section[aria-label=Projects] a[href=?]", project_issues_path(projects(:billing))
  end

  test "chips work in the global search and link into each project's list" do
    get search_path(q: "is:unresolved level:warning")

    assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:card_error))
    assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:nomethod)), count: 0
    assert_select "a[href=?]", project_issues_path(projects(:storefront), q: "is:unresolved level:warning")
    assert_select ".chip", text: "level:warning"
  end

  test "user search by email" do
    get search_path(q: "user:mara@example.com")

    assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:nomethod))
    assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:regressed))
    assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:card_error)), count: 0
  end

  test "an outsider never sees another account's projects or issues" do
    sign_in_as users(:outsider)

    get search_path(q: "error")

    assert_response :success
    assert_no_match(/storefront|NoMethodError|price_cents/, response.body)

    get search_path(q: "GS-1042")

    assert_response :success
    assert_no_match(/price_cents/, response.body)
  end
end
