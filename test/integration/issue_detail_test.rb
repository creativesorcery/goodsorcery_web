require "test_helper"

class IssueDetailTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:storefront)
    @issue = issues(:nomethod)
    sign_in_as users(:alex)
  end

  test "renders the hero, stats, chart and latest occurrence" do
    get project_issue_path(@project, @issue)

    assert_response :success
    assert_select "title", "NoMethodError in CheckoutsController#create — Good Sorcery"
    assert_select "h1.font-mono.text-coral-300", "NoMethodError"
    assert_select "p.font-display span.font-mono", "price_cents"
    assert_select "p.font-mono", text: /CheckoutsController#create · app\/services\/cart_total.rb:42 in line_total/
    assert_select "span.chip", text: "New · unresolved"
    assert_select "span.chip.chip-coral", text: "production"
    assert_select "turbo-frame##{dom_id(@issue, :stats)} dd", text: "1,284"
    assert_select "turbo-frame##{dom_id(@issue, :chart)} svg rect", minimum: 24
    assert_select "turbo-frame#occurrence[data-turbo-action=advance]"
    assert_select "turbo-cable-stream-source[channel=AuthorizedStreamsChannel]"
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
  end

  test "an issue that reached production carries the coral marker and a timeline entry" do
    @issue.update_columns(environments: %w[staging production], reached_production_at: 2.hours.ago)
    @issue.activities.create!(kind: "reached_production")

    get project_issue_path(@project, @issue)

    assert_select "span[title^=?] span.chip.chip-coral:not(.chip-sm)", "First seen in production", text: /Reached production/
    assert_select "##{dom_id(@issue, :activities)} li", text: /Reached production: first seen there after other environments/
  end

  test "an issue without the milestone has no marker" do
    get project_issue_path(@project, @issue)

    assert_select "span.chip", text: /Reached production/, count: 0
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
    assert_select "div[data-toggle-target=expanded] span.font-mono", text: "activerecord", count: 2
    assert_select "details summary", text: /app\/controllers\/checkouts_controller.rb/
    assert_select "pre[data-clipboard-target=source]", text: /\ANoMethodError: undefined method `price_cents' for nil \(cart 88123, mara@example.com\)/
  end

  test "a non-Ruby occurrence shows columns, modules, packages and its runtime list" do
    occurrence = occurrences(:nomethod_latest)
    data = JSON.parse(occurrence.payload)
    data["exception"]["backtrace"] = [
      { "file" => "src/cart.rs", "line" => 42, "column" => 17, "method" => "line_total", "module" => "shop::cart", "in_app" => true,
        "package" => "shop" },
      { "file" => "crates/tokio-1.41.0/src/runtime/park.rs", "line" => 281, "method" => "block_on", "in_app" => false, "package" => "tokio" }
    ]
    data["context"] = { "runtime" => [ { "name" => "Rust", "version" => "1.82.0" }, { "name" => "axum", "version" => "0.8.1" } ] }
    occurrence.update!(payload: data.to_json)

    get project_issue_path(@project, @issue)

    assert_select "span.text-ink-400", text: ":17"
    assert_select "span.text-ink-300", text: "shop::cart"
    assert_select "button[data-toggle-target=collapsed]", text: /1 framework frame hidden\s+\(tokio\)/
    assert_select "pre[data-clipboard-target=source]", text: /src\/cart\.rs:42:17 in shop::cart line_total/
    assert_select "#context-environment span", text: "runtime.Rust"
    assert_select "#context-environment span", text: "1.82.0"
  end

  test "locals and context show [FILTERED] values muted" do
    get project_issue_path(@project, @issue)

    assert_select "span.text-ink-400", text: "[FILTERED]", minimum: 4
    assert_select "#context-params pre span.tok-s", text: "\"coupon\""
    assert_select "#context-headers span", text: "User-Agent"
    assert_select "#context-environment span", text: "runtime.ruby"
    assert_select "#context-request span.text-lilac-300", text: "CheckoutsController#create"
  end

  test "a request occurrence opens on Request and shows the Job tab's empty state" do
    get project_issue_path(@project, @issue)

    assert_select "[role=tab]", count: 6
    assert_select "[role=tab][aria-selected=true]", text: "Request"
    assert_select "#context-tab-job[aria-selected=false]", text: "Job"
    assert_select "#context-request:not([hidden])"
    assert_select "#context-job[hidden][role=tabpanel][aria-labelledby=context-tab-job] p", text: "No job was captured with this occurrence."
  end

  test "a job occurrence opens on the Job tab with its fields and arguments" do
    get project_issue_path(@project, issues(:regressed))

    assert_response :success
    assert_select "[role=tab][aria-selected=true]", text: "Job"
    assert_select "#context-request[hidden] p", text: "No request was captured with this occurrence."
    assert_select "#context-job:not([hidden])" do
      assert_select "span", text: "Active Job"
      assert_select "span.text-lilac-300", text: "Orders::PlaceJob"
      assert_select "span", text: "orders"
      assert_select "span", text: "Provider job ID"
      assert_select "span", text: "Mailer", count: 0
      assert_select "pre span.tok-s", text: "\"gid://shop/Order/5521\""
      assert_select "pre span.text-ink-400", text: "[FILTERED]"
    end
  end

  test "job arguments are escaped, never interpreted as HTML" do
    occurrence = occurrences(:regressed_latest)
    data = occurrence.data.deep_dup
    data["job"]["queue"] = "<b>q</b>"
    data["job"]["arguments"] = [ "<script>alert(1)</script>" ]
    occurrence.update_column(:payload, data.to_json)

    get project_issue_path(@project, issues(:regressed))

    assert_no_match "<script>alert(1)</script>", response.body
    assert_no_match "<b>q</b>", response.body
    assert_includes response.body, "&lt;b&gt;q&lt;/b&gt;"
  end

  test "outsiders get 404 for a job occurrence" do
    sign_in_as users(:outsider)

    get project_issue_path(@project, issues(:regressed))

    assert_response :not_found
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
    assert_select "##{dom_id(@issue, :activities)} li", text: /Alex assigned themselves/
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
