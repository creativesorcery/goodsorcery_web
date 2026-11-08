require "test_helper"
require_relative "../../../test_helpers/performance_pages_test_helper"

class Projects::Performance::TransactionsControllerTest < ActionDispatch::IntegrationTest
  include ApmFixtureClock

  include PerformancePagesTestHelper, ActionView::RecordIdentifier

  setup do
    @project = projects(:storefront)
    @checkout = apm_transactions(:checkout_create)
    sign_in_as users(:philip)
  end

  test "the header shows the name, route, file and the Slower line" do
    get project_performance_transaction_path(@project, @checkout)

    assert_response :success
    assert_select ".eyebrow", "Web request · production"
    assert_select "h1", "CheckoutsController#create"
    assert_select "span", "POST /checkout"
    assert_select "span", "app/controllers/checkouts_controller.rb"
    assert_select ".chip-coral", /p95 in the last hour is \d+\.\d× the day's/
    assert_select "nav[aria-label=Breadcrumb] a[href=?]", project_performance_path(@project, env: "production", range: "1d"), text: "Performance"
  end

  test "the ribbon is Requests, Average, p75, p90, p95, p99 and Failed with Last hour sublines and the issues link" do
    get project_performance_transaction_path(@project, @checkout)

    keys = css_select("dl[aria-label=Summary] [data-stat]").map { it["data-stat"] }
    assert_equal %w[requests average p75 p90 p95 p99 failed], keys
    assert_select "[data-stat=requests] dt", "Requests · 24h"
    assert_select "[data-stat=requests] dd", /per minute · last hour/
    %w[average p75 p90 p95 p99].each { |key| assert_select "[data-stat=#{key}] dd", /Last hour/ }
    assert_select "[data-stat=p95] dd.text-coral-300", /· ▲ \d+\.\d×/
    assert_select "[data-stat=p99] dd.text-coral-300", count: 0
    assert_select "[data-stat=p95][class*=bg-coral-500]"
    assert_select "[data-stat=p99][class*=bg-coral-500]", count: 0
    assert_select "[data-stat=failed] dd", /Last hour \d/
    assert_select "[data-stat=failed] a[href=?]", project_issues_path(@project, q: "is:unresolved CheckoutsController#create", env: "production"),
      text: "1 issue"
  end

  test "the response chart has five lines and Where time goes five bars with the summary sentence" do
    get project_performance_transaction_path(@project, @checkout)

    legend = css_select("#apm_response_heading + div span").map { it.text.strip }
    assert_equal %w[Average p75 p90 p95 p99], legend
    assert_select "svg[aria-label^='Average, p75, p90, p95 and p99'] path[fill=none]", 5
    assert_select "svg[aria-label^='Average, p75, p90, p95 and p99'] path[stroke-dasharray='5 4']", 1
    assert_equal %w[average 75 90 95 99], css_select("[data-bar]").map { it["data-bar"] }
    assert_select "[data-bar=95] .text-coral-300"
    assert_select "p", /\AAround p95 and p99, .+ takes the most time \(\d+% and \d+%\)\. Typical requests/
  end

  test "Where time goes draws its bars on one scale, so the longest value spans the width" do
    get project_performance_transaction_path(@project, @checkout)

    widths = %w[average 75 90 95 99].to_h { |key| [ key, css_select("[data-bar='#{key}'] clipPath rect").first["width"].to_f ] }
    assert_in_delta 100.0, widths.values.max, 0.01
    assert_operator widths["average"], :<, widths["99"]
  end

  test "Errors on this endpoint lists only unresolved issues of this transaction and environment" do
    get project_performance_transaction_path(@project, @checkout)

    assert_select "#errors a[href=?]", project_issue_path(@project, issues(:nomethod)) do
      assert_select "span", /GS-1042 · 1,284 events/
      assert_select ".chip-coral", /New/
    end
    assert_select "#errors a", 1

    get project_performance_transaction_path(@project, apm_transactions(:products_show))
    assert_select "#errors p", "No unresolved issues from this endpoint."
    assert_select "[data-stat=failed] dd", /no issues/
  end

  test "slow traces are the slowest first with the error chip linking to the issue" do
    get project_performance_transaction_path(@project, @checkout)

    assert_select "turbo-frame##{dom_id(@checkout, :traces)}[data-turbo-action=advance]" do
      links = css_select("a[aria-label^='Trace of']").map { it["href"] }
      expected = [ apm_traces(:checkout_slow), apm_traces(:checkout_failed), apm_traces(:checkout_old_hour) ]
      assert_equal expected.map { project_performance_trace_path(@project, it, env: "production", range: "1d") }, links
      assert_select "a.chip-coral[href=?][data-turbo-frame=_top]", project_issue_path(@project, issues(:nomethod)), text: "GS-1042"
      assert_select ".chip-coral", "500"
      assert_select "span", /3 of 3 traces in the last 24 hours/
    end
  end

  test "Newest sorts by start time and the frame request renders only the frame" do
    get project_performance_transaction_path(@project, @checkout, traces: "newest"), headers: { "Turbo-Frame" => dom_id(@checkout, :traces) }

    assert_response :success
    assert_select "h1", count: 0
    assert_select "nav[aria-label='Sort traces'] a[aria-current=true]", "Newest"
    first = css_select("a[aria-label^='Trace of']").first["href"]
    assert_equal project_performance_trace_path(@project, apm_traces(:checkout_failed), env: "production", range: "1d"), first
  end

  test "traces come 20 per page with next and previous links" do
    transaction = create_apm_transaction(@project, "ReportsController#index")
    25.times { |i| create_apm_trace(transaction, minutes_ago: i + 1, duration_ms: 100.0 + i) }

    get project_performance_transaction_path(@project, transaction)
    assert_select "a[aria-label^='Trace of']", 20
    assert_select "span", /20\s+of 25 traces/
    assert_select "a[href=?]", project_performance_transaction_path(@project, transaction, env: "production", range: "1d", page: 2), text: "Next 20 →"

    get project_performance_transaction_path(@project, transaction, page: 2)
    assert_select "a[aria-label^='Trace of']", 5
    assert_select "span", /21–25\s+of 25 traces/
    assert_select "a", text: "← Previous 20"
    assert_select "a", text: "Next 20 →", count: 0
  end

  test "a huge page number shows an empty page instead of failing" do
    get project_performance_transaction_path(@project, @checkout, page: "99999999999999999999")
    assert_response :success
    assert_select "a[aria-label^='Trace of']", 0
  end

  test "the page costs the same number of statements with 3 or 25 traces" do
    few = count_request_queries { get project_performance_transaction_path(@project, @checkout) }
    22.times { |i| create_apm_trace(@checkout, minutes_ago: 30 + i) }
    many = count_request_queries { get project_performance_transaction_path(@project, @checkout) }

    assert_equal few, many
  end

  test "a job's page shows its adapter, queue and runs" do
    get project_performance_transaction_path(@project, apm_transactions(:place_order_job))

    assert_select ".eyebrow", "Background job · production"
    assert_select "span", "sidekiq · critical"
    assert_select "[data-stat=requests] dt", "Runs · 24h"
    assert_select "h2", "Errors on this job"
  end

  test "sends no-store, has no inline styles and never shows trace data" do
    get project_performance_transaction_path(@project, @checkout)

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_match(/style="/, response.body)
    assert_no_match SECRET, response.body
  end

  test "total rows, other apps' transactions and other accounts are 404s" do
    get project_performance_transaction_path(@project, apm_transactions(:storefront_web_total))
    assert_response :not_found

    get project_performance_transaction_path(@project, apm_transactions(:billing_invoices))
    assert_response :not_found

    get project_performance_transaction_path(projects(:umbrella_app), apm_transactions(:umbrella_home))
    assert_response :not_found

    sign_in_as users(:outsider)
    get project_performance_transaction_path(@project, @checkout)
    assert_response :not_found
  end

  test "signed-out visitors go to sign in" do
    sign_out
    get project_performance_transaction_path(@project, @checkout)

    assert_redirected_to new_session_path
  end
end
