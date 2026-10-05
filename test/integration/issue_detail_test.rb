require "test_helper"

class IssueDetailTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    sign_in_as users(:philip)
  end

  test "renders the hero, stats, chart and latest occurrence" do
    get project_issue_path(@project, @issue)

    assert_response :success
    assert_select "title", "NoMethodError in CheckoutsController#create — Good Sorcery"
    assert_select "h1.font-mono.text-coral-300", "NoMethodError"
    assert_select "p.font-display span.font-mono", "price_cents"
    assert_select "p.font-mono", text: /CheckoutsController#create · app\/services\/cart_total.rb:42 in line_total/
    assert_select "span.chip", text: "New · unresolved"
    assert_select "turbo-frame##{dom_id(@issue, :stats)} dd", text: "1,284"
    assert_select "turbo-frame##{dom_id(@issue, :chart)} svg rect", minimum: 24
    assert_select "turbo-frame#occurrence[data-turbo-action=advance]"
    assert_select "turbo-cable-stream-source[channel=AuthorizedStreamsChannel]"
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
  end

  test "never lets browsers or proxies store the page" do
    get project_issue_path(@project, @issue)

    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "backtrace is app-first with the top frame expanded and framework runs folded" do
    get project_issue_path(@project, @issue)

    assert_select ".bg-coral-500\\/15", text: /variant\.price_cents \* item\.quantity/
    assert_select "span", text: "42"
    assert_select "button[data-toggle-target=collapsed]", text: /2 framework frames hidden\s+\(activerecord\)/
    assert_select "button[data-toggle-target=collapsed]", text: /2 framework frames hidden\s+\(actionpack\)/
    assert_select "div[data-toggle-target=expanded][hidden]", count: 2
    assert_select "details summary", text: /app\/controllers\/checkouts_controller.rb/
    assert_select "pre[data-clipboard-target=source]", text: /\ANoMethodError: undefined method `price_cents' for nil \(cart 88123, mara@example.com\)/
  end

  test "locals and context show [FILTERED] values muted" do
    get project_issue_path(@project, @issue)

    assert_select "span.text-ink-400", text: "[FILTERED]", minimum: 4
    assert_select "#context-params pre span.tok-s", text: "\"coupon\""
    assert_select "#context-headers span", text: "User-Agent"
    assert_select "#context-environment span", text: "runtime.ruby"
    assert_select "#context-request span.text-lilac-300", text: "CheckoutsController#create"
  end

  test "breadcrumbs end at the coral error node" do
    get project_issue_path(@project, @issue)

    assert_select "li[data-breadcrumb-filter-target=item]", count: 4
    assert_select "li[data-category=sql] span.bg-lilac-400"
    assert_select "li span", text: "−412ms"
    assert_select "li:last-child span.font-mono.text-coral-300", text: "NoMethodError raised"
    assert_select "button[data-breadcrumb-filter-category-param=all]", text: "all 4"
  end

  test "right rail: navigator, affected user, tags and activity" do
    get project_issue_path(@project, @issue)

    assert_select "a[href=?]", project_issue_occurrence_path(@project, @issue, occurrences(:nomethod_oldest))
    assert_select "span[aria-label='Newer occurrence'][aria-disabled=true]"
    assert_select "span", text: /2\s+of 2 stored/
    assert_select "div", text: "Mara Lindqvist"
    assert_select "div.font-mono", text: "id 5521 · mara@…"
    assert_no_match "mara@example.com\"", response.body.split("data-clipboard-target").first
    assert_select "a[href*='user%3A']", text: "all their errors"
    assert_select "div", text: /← suspicious/
    assert_select "##{dom_id(@issue, :activities)} li", text: /Philip assigned themselves/
    assert_select "##{dom_id(@issue, :activities)} p", text: /discontinued variants/
    assert_select "form##{dom_id(@issue, :note_form)} textarea[placeholder='Leave a note for the coven…']"
  end

  test "an issue without stored occurrences still renders" do
    issue = issues(:card_error)

    get project_issue_path(@project, issue)

    assert_response :success
    assert_select "h2", "No stored occurrences"
    assert_select "p", text: "No user was attached to this occurrence."
  end

  test "captured data is escaped, never interpreted as HTML" do
    occurrence = occurrences(:nomethod_latest)
    data = occurrence.data.deep_dup
    data["user"]["name"] = "<script>alert(1)</script>"
    data["params"]["coupon"] = "<img src=x onerror=alert(1)>"
    occurrence.update_column(:payload, data.to_json)

    get project_issue_path(@project, @issue)

    assert_response :success
    assert_no_match "<script>alert(1)</script>", response.body
    assert_no_match "<img src=x", response.body
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_issue_path(@project, @issue)

    assert_response :not_found
  end

  test "resolved and ignored issues offer reopen" do
    get project_issue_path(@project, issues(:resolved_issue))

    assert_select "span.btn", text: "✓ Resolved"
    assert_select "form[action=?] button", project_issue_resolution_path(@project, issues(:resolved_issue)), text: "↺ Reopen"

    get project_issue_path(@project, issues(:ignored_issue))

    assert_select "form[action=?] button", project_issue_ignore_path(@project, issues(:ignored_issue)), text: "Stop ignoring"
  end
end
