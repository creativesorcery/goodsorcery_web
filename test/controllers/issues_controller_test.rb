require "test_helper"

class IssuesControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    @project = projects(:storefront)
    sign_in_as users(:philip)
  end

  test "requires authentication" do
    sign_out

    get project_issues_path(@project)

    assert_redirected_to new_session_path
  end

  test "an outsider gets 404 for another account's project" do
    sign_in_as users(:outsider)

    get project_issues_path(@project)

    assert_response :not_found
  end

  test "a non-scalar or junk page param falls back to the first page" do
    [ "page[a]=1", "page[]=2", "page=abc" ].each do |query|
      get "#{project_issues_path(@project)}?#{query}"
      assert_response :success, query
      assert_select "##{dom_id(issues(:nomethod), :row)}"
    end
  end

  test "lists unresolved issues by default" do
    get project_issues_path(@project)

    assert_response :success
    assert_select "title", "Issues · storefront — Good Sorcery"
    assert_select "h1", /Issues\s+— 3 unresolved/
    assert_select "##{dom_id(issues(:nomethod), :row)}"
    assert_select "##{dom_id(issues(:regressed), :row)}"
    assert_select "##{dom_id(issues(:card_error), :row)}"
    assert_select "##{dom_id(issues(:resolved_issue), :row)}", count: 0
    assert_select "##{dom_id(issues(:ignored_issue), :row)}", count: 0
    assert_select "##{dom_id(issues(:billing_timeout), :row)}", count: 0
  end

  test "rows show tone, short id, counts and the assignee" do
    get project_issues_path(@project)

    nomethod = "##{dom_id(issues(:nomethod), :row)}"
    assert_select "#{nomethod}[target=_top] .edge-stripe.edge-coral"
    assert_select "#{nomethod} .text-coral-300", text: "NoMethodError"
    assert_select "#{nomethod} .chip-coral", text: /New/
    assert_select "#{nomethod} a[href=?]", project_issue_path(@project, issues(:nomethod)), text: "undefined method `price_cents' for nil"
    assert_select nomethod, text: /GS-1042/
    assert_select nomethod, text: /1,284/
    assert_select "#{nomethod} span[title=?]", "Philip Nguyen"
    assert_select "#{nomethod} svg rect", 24
    assert_select "#{nomethod} input[type=checkbox][form=bulk_triage][name='issue_ids[]'][value=?]", issues(:nomethod).id.to_s

    regressed = "##{dom_id(issues(:regressed), :row)}"
    assert_select "#{regressed} .edge-stripe.edge-lilac"
    assert_select "#{regressed} .chip-lilac", text: /Regressed/

    card_error = "##{dom_id(issues(:card_error), :row)}"
    assert_select "#{card_error} .edge-stripe", count: 0
    assert_select "#{card_error} .text-ink-100", text: "Stripe::CardError"
  end

  test "rows carry environment chips in their tone and play down issues never seen in production" do
    issues(:card_error).update_columns(environments: %w[staging])

    get project_issues_path(@project)

    regressed = "##{dom_id(issues(:regressed), :row)}"
    assert_select "#{regressed} .chip.chip-sm.chip-coral", text: "production"
    assert_select "#{regressed} .chip.chip-sm.chip-lilac", text: "staging"
    assert_select "#{regressed} .opacity-60", count: 0

    card_error = "##{dom_id(issues(:card_error), :row)}"
    assert_select "#{card_error} .chip.chip-sm.chip-lilac", text: "staging"
    assert_select "#{card_error} .min-w-0.opacity-60 a[href=?]", project_issue_path(@project, issues(:card_error))
  end

  test "captured text is escaped" do
    issues(:card_error).update_columns(message: "<script>alert(1)</script>")

    get project_issues_path(@project)

    assert_no_match "<script>alert(1)</script>", response.body
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "tabs carry counts and rewrite only the status chips" do
    get project_issues_path(@project, q: "is:unresolved env:production")

    assert_select "nav[aria-label=Triage] a.tab", 5
    assert_select "a.tab[aria-selected=true]", text: /Unresolved\s*3/
    assert_select "a.tab[href=?]", project_issues_path(@project, q: "is:for_review env:production"), text: /For review\s*2/
    assert_select "a.tab[href=?]", project_issues_path(@project, q: "is:unresolved assigned:me env:production"), text: /Assigned to me\s*1/
    assert_select "a.tab[href=?]", project_issues_path(@project, q: "is:resolved env:production")
  end

  test "resolved tab" do
    get project_issues_path(@project, q: "is:resolved")

    assert_select "a.tab[aria-selected=true]", text: "Resolved"
    assert_select "##{dom_id(issues(:resolved_issue), :row)}"
    assert_select "##{dom_id(issues(:resolved_issue), :row)} button", text: "Reopen"
    assert_select "##{dom_id(issues(:nomethod), :row)}", count: 0
  end

  test "query chips render as removable pills and the text input keeps free text" do
    get project_issues_path(@project, q: "is:unresolved level:warning stripe")

    assert_select "form[role=search] .chip", 2
    assert_select "form[role=search] .chip a[href=?]", project_issues_path(@project, q: "is:unresolved stripe"), text: "×"
    assert_select "input[type=hidden][name=chips][value=?]", "is:unresolved level:warning"
    assert_select "input[name=text][value=?]", "stripe"
    assert_select "##{dom_id(issues(:card_error), :row)}"
    assert_select "##{dom_id(issues(:nomethod), :row)}", count: 0
  end

  test "the filter bar form composes chips and text" do
    get project_issues_path(@project, chips: "is:unresolved", text: "level:error checkout")

    assert_select ".chip", text: /level:\s*error/
    assert_select "##{dom_id(issues(:nomethod), :row)}"
    assert_select "##{dom_id(issues(:card_error), :row)}", count: 0
  end

  test "filters menu lists environments and levels" do
    get project_issues_path(@project)

    assert_select ".menu a[href=?]", project_issues_path(@project, q: "is:unresolved env:production")
    assert_select ".menu a[href=?]", project_issues_path(@project, q: "is:unresolved env:staging")
    assert_select ".menu a[href=?]", project_issues_path(@project, q: "is:unresolved level:fatal")
  end

  test "sort menu and sorting" do
    get project_issues_path(@project, sort: "events")

    assert_select "button", text: /Sort: Events/
    assert_select ".menu a[href=?]", project_issues_path(@project, q: "is:unresolved"), text: "Last seen"
    ids = css_select("[id^=row_issue_]").map { |frame| frame["id"] }
    assert_equal dom_id(issues(:card_error), :row), ids.first
  end

  test "user search by email" do
    get project_issues_path(@project, q: "user:sam@example.com")

    assert_select "[id^=row_issue_]", 1
    assert_select "##{dom_id(issues(:nomethod), :row)}"
  end

  test "default state has the live prepend target and stream; filtered state has no prepend target" do
    get project_issues_path(@project)

    assert_select "##{dom_id(@project, :new_issues)}"
    assert_select "turbo-cable-stream-source[channel=AuthorizedStreamsChannel]"
    assert_select "turbo-frame##{dom_id(@project, :summary)}[src=?][complete]", project_summary_path(@project)

    get project_issues_path(@project, q: "is:unresolved level:error")

    assert_select "##{dom_id(@project, :new_issues)}", count: 0
  end

  test "the summary frame follows the env chip" do
    get project_issues_path(@project, q: "is:unresolved env:staging")

    assert_select "turbo-frame##{dom_id(@project, :summary)}[src=?]", project_summary_path(@project, env: "staging")
    assert_select ".eyebrow", "storefront · staging"
    assert_select "h1", /1 unresolved/
  end

  test "bulk bar offers resolve, ignore and assign to members only" do
    get project_issues_path(@project)

    assert_select "form#bulk_triage[action=?]", project_bulk_triage_path(@project) do
      assert_select "button[name=triage][value=resolve]"
      assert_select "button[name=triage][value=ignore]"
      assert_select "button[name=triage][value=reopen]", count: 0
      assert_select "button[name=assignee_id]", 2
      assert_select "button[name=assignee_id][value=?]", users(:outsider).id.to_s, count: 0
    end
    assert_select "[data-bulk-selection-target=bar][hidden]"
    assert_no_match(/Merge/, response.body)
  end

  test "load more pages through a frame" do
    create_issues(30)

    get project_issues_path(@project)

    assert_select "[id^=row_issue_]", 25
    assert_select "turbo-frame#issues_page_2 a[href=?]", project_issues_path(@project, q: "is:unresolved", sort: "last_seen", page: 2),
      text: "load more"
    assert_select "turbo-frame#issues_page_2", text: /Showing 25 of 33/

    get project_issues_path(@project, q: "is:unresolved", sort: "last_seen", page: 2), headers: { "Turbo-Frame" => "issues_page_2" }

    assert_response :success
    assert_select "turbo-frame#issues_page_2"
    assert_select "[id^=row_issue_]", 8
    assert_select "h1", count: 0
    assert_select "turbo-frame#issues_page_3", count: 0
  end

  test "empty states" do
    get project_issues_path(projects(:marketing))

    assert_response :success
    assert_select "h2", text: /Listening for the first error/

    get project_issues_path(@project, q: "is:unresolved no-such-thing")

    assert_select "h2", "No issues match"
  end

  test "renders without N+1 queries: query count does not grow with rows" do
    get project_issues_path(@project)
    baseline = count_queries { get project_issues_path(@project) }

    create_issues(20, assignee: users(:jo))
    with_more_rows = count_queries { get project_issues_path(@project) }

    assert_response :success
    assert_select "[id^=row_issue_]", 23
    assert_equal baseline, with_more_rows
  end

  test "sends no-store" do
    get project_issues_path(@project)

    assert_includes response.headers["Cache-Control"], "no-store"
  end

  private
    def create_issues(count, assignee: nil)
      count.times do |index|
        issue = @project.issues.create!(number: 6_000 + index, fingerprint: Digest::SHA256.hexdigest("ctl-#{index}"),
          exception_class: "RuntimeError", message: "boom #{index}", first_seen_at: 3.days.ago,
          last_seen_at: (index + 20).minutes.ago, environments: [ "production" ], assignee:)
        issue.hourly_counts.create!(hour: Time.current.beginning_of_hour, count: index + 1)
      end
    end

    def count_queries(&block)
      count = 0
      # Cached hits count too: across requests in one test the query cache may
      # answer, but each one still shows a query the page issued.
      counter = ->(*, payload) { count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
end
