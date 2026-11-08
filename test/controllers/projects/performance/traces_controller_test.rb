require "test_helper"
require_relative "../../../test_helpers/performance_pages_test_helper"

class Projects::Performance::TracesControllerTest < ActionDispatch::IntegrationTest
  include ApmFixtureClock

  include PerformancePagesTestHelper

  setup do
    @project = projects(:storefront)
    @trace = apm_traces(:checkout_slow)
    sign_in_as users(:philip)
  end

  test "the header, chips and layer summary of a slow request" do
    get project_performance_trace_path(@project, @trace)

    assert_response :success
    assert_select ".eyebrow", /Slow trace · the slowest request in its minute/
    assert_select "h1", "POST /checkout"
    assert_select "div.font-mono", /CheckoutsController#create · \w{3} \d+, \d\d:\d\d:\d\d · web-2 · request 7f3a9c1e/
    chips = css_select("[aria-label='Trace summary'] .chip").map { it.text.strip }
    assert_equal [ "2.94 s", "200 OK", "43 SQL queries", "2 HTTP calls", "1 N+1 pattern" ], chips
    assert_select "section[aria-label='Time by layer']" do
      assert_select "span", /Database\s*1.22 s\s*42%/
      assert_select "span", /External HTTP\s*1.23 s\s*42%/
    end
    assert_select "nav[aria-label=Breadcrumb] span", "trace #{@trace.short_id}"
  end

  test "the timeline groups repeated queries and the N+1 detail explains them" do
    get project_performance_trace_path(@project, @trace)

    assert_select "span", "Action"
    assert_select "span[title=?]", 'SELECT "users" WHERE "id" = $1'
    assert_select "a[href='#span-detail'][aria-current=true] .chip-lilac", "N+1 ×38"
    assert_select "span", "POST api.taxjar.com/v2/taxes"
    assert_select "span", "checkouts/create.html.erb"
    assert_select "span", "enqueue Orders::PlaceJob"
    assert_select "#span-detail" do
      assert_select "h2", "One query, run 38 times"
      assert_select "pre .tok-k", "SELECT"
      assert_select "pre .tok-n", "$1"
      assert_select "p", "Values become placeholders inside your app, before anything is sent."
      assert_select "dd", "38"
      assert_select "dd", "1.18 s"
      assert_select "p", /Called from\s*app\/services\/cart_total.rb:27\s*in\s*total_cents/
      assert_select ".code .bg-lilac-400\\/15", /item.product.price_cents/
      assert_select "p", "This query ran 38 times in one request. Load the rows in one query (a join, an IN list or a batch load) instead of one per item."
      assert_select "p", text: /includes/, count: 0
    end
  end

  test "the request panel and no errors" do
    get project_performance_trace_path(@project, @trace)

    facts = css_select("#apm_request_heading + dl dt").map(&:text)
    assert_equal %w[Status Host Started Runtime GC Allocations], facts
    assert_select "dd", "web-2 · Puma worker 3"
    assert_select "dd", "Rails 8.0.2 · Ruby 3.4.1"
    assert_select "dd", "14 ms · 3 runs"
    assert_select "dd", "1.4M objects"
    assert_select "p", "Traces carry no params, headers, cookies or bodies."
    assert_select "p", "None. Requests that raise link straight to their issue."
  end

  test "a failed request links its error to the issue" do
    get project_performance_trace_path(@project, apm_traces(:checkout_failed))

    assert_select "[aria-label='Trace summary'] .chip-coral", "500 Internal Server Error"
    assert_select "section a[href=?]", project_issue_path(@project, issues(:nomethod)) do
      assert_select "span", "GS-1042"
    end
  end

  test "a reported error whose event is gone says so" do
    @trace.update_columns(error_event_uuid: "0192f7a4-6c1e-7b3a-9d21-000000000000")
    get project_performance_trace_path(@project, @trace)

    assert_select "p", "Error reported, but its event is no longer stored."
  end

  test "older and newer traces of the same transaction" do
    get project_performance_trace_path(@project, @trace)

    assert_select "a[href=?]", project_performance_trace_path(@project, apm_traces(:checkout_old_hour), env: "production", range: "1d"),
      text: "← Older trace"
    assert_select "a[href=?]", project_performance_trace_path(@project, apm_traces(:checkout_failed), env: "production", range: "1d"),
      text: "Newer trace →"

    get project_performance_trace_path(@project, apm_traces(:checkout_failed))
    assert_select "span.btn[aria-disabled=true]", "Newer trace →"
  end

  test "a closed hour's trace says it is one of the 3 slowest" do
    get project_performance_trace_path(@project, apm_traces(:checkout_old_hour))

    assert_select ".eyebrow", /one of the 3 slowest in its hour/
  end

  test "SQL and code from the trace render escaped" do
    transaction = apm_transactions(:checkout_create)
    span = { type: "sql", offset_ms: 1.0, duration_ms: 50.0, count: 12, sql: "SELECT \"<script>alert(1)</script>\".* FROM \"x\" WHERE \"id\" = $1",
             call_site: { file: "app/x.rb", line: 2, method: "<b>m</b>", context: { start_line: 1, lines: [ "a", "<img src=x onerror=alert(2)>" ] } } }
    trace = create_apm_trace(transaction, minutes_ago: 50, n_plus_one_count: 1, payload: { request: { method: "GET", path: "/<i>x</i>" }, spans: [ span ] })

    get project_performance_trace_path(@project, trace)

    assert_response :success
    assert_no_match(/<script>alert|<img src=x|<b>m<\/b>|<i>x<\/i>/, response.body)
    assert_match "&lt;script&gt;alert(1)&lt;/script&gt;", response.body
    assert_match "&lt;img src=x onerror=alert(2)&gt;", response.body
  end

  test "sends no-store and has no inline styles" do
    get project_performance_trace_path(@project, @trace)

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_match(/style="/, response.body)
  end

  test "a trace replaced within the retention is no longer kept (410)" do
    get project_performance_trace_path(@project, Apm::TraceId.generate(2.hours.ago))

    assert_response :gone
    assert_select "h1", "This trace is no longer kept"
    assert_select "p", /A slower request replaced this one/
    assert_select "a[href=?]", project_performance_path(@project), text: "Back to Performance"
  end

  test "self-hosted, a trace past the retention names the instance's days and offers no upgrade" do
    get project_performance_trace_path(@project, Apm::TraceId.generate(40.days.ago))

    assert_response :gone
    assert_select "p", /This instance keeps performance data for 30 days/
    assert_no_match "Upgrade", response.body
  end

  test "hosted, a trace beyond the plan's days offers to keep more days" do
    with_hosted_mode do
      with_upgrade_url("https://billing.example/upgrade") do
        get project_performance_trace_path(@project, Apm::TraceId.generate(5.days.ago))
        assert_response :gone
        assert_select "p", /Good Sorcery keeps performance data for 1 day on this account/
        assert_select "a[href='https://billing.example/upgrade']", "Upgrade to keep more days"

        get project_performance_trace_path(@project, Apm::TraceId.generate(40.days.ago))
        assert_response :gone
        assert_no_match "Upgrade to keep more days", response.body
      end
    end
  end

  test "hosted without an upgrade URL, a trace beyond the account's days drops the upgrade line" do
    with_hosted_mode { with_upgrade_url(nil) { get project_performance_trace_path(@project, Apm::TraceId.generate(5.days.ago)) } }

    assert_response :gone
    assert_select "h1", "This trace is no longer kept"
    assert_select "p", /Good Sorcery keeps performance data for 1 day on this account/
    assert_select "a[href=?]", project_performance_path(@project), text: "Back to Performance"
    assert_no_match "Upgrade", response.body
  end

  test "unknown, non-v7, future and other apps' trace ids are 404s" do
    [ SecureRandom.uuid, "not-a-uuid", Apm::TraceId.generate(2.hours.from_now), Apm::TraceId.generate(400.days.ago) ].each do |id|
      get project_performance_trace_path(@project, id)
      assert_response :not_found, id
    end

    billing_transaction = apm_transactions(:billing_invoices)
    billing_trace = create_apm_trace(billing_transaction, minutes_ago: 20)
    get project_performance_trace_path(@project, billing_trace)
    assert_response :not_found
  end

  test "another account's trace and app are 404s, and signed-out visitors go to sign in" do
    get project_performance_trace_path(projects(:umbrella_app), apm_traces(:umbrella_trace))
    assert_response :not_found

    sign_in_as users(:outsider)
    get project_performance_trace_path(@project, @trace)
    assert_response :not_found
    get project_performance_trace_path(@project, Apm::TraceId.generate(2.hours.ago))
    assert_response :not_found

    sign_out
    get project_performance_trace_path(@project, @trace)
    assert_redirected_to new_session_path
  end
end
