require "test_helper"

# Every MCP tool through POST /mcp: happy paths, not-found paths (unknown and
# other-account ids look the same), the untrusted-data notice, request_data
# redaction, secrets that must never appear, triage effects and audit rows,
# and fixed query counts.
class McpToolsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ApmFixtureClock

  SECRETS = [ "uptime-fixture-secret", *FIXTURE_TOKENS.values, *PAT_FIXTURE_TOKENS.values ].freeze
  PERSONAL = [ "mara@example.com", "Mara Lindqvist", "81.2.69.160", "Mozilla/5.0", "card_token" ].freeze

  def structured(result) = result.fetch("structuredContent")

  def assert_tool_error(result, message)
    assert result["isError"], result.inspect
    assert_match message, mcp_text(result)
  end

  def assert_no_secrets(result)
    json = result.to_json
    SECRETS.each { |secret| assert_not_includes json, secret }
  end

  def assert_untrusted_notice(result)
    assert_equal Mcp::UNTRUSTED_NOTICE, structured(result)["notice"]
    assert mcp_text(result).start_with?(Mcp::UNTRUSTED_NOTICE)
  end

  # ── list_apps ────────────────────────────────────────────────

  test "list_apps lists the account's apps with unresolved counts" do
    result = mcp_tool(:philip_read, "list_apps")

    apps = structured(result)["apps"].index_by { it["slug"] }
    assert_equal %w[billing-api marketing-site storefront], apps.keys
    assert_equal 3, apps["storefront"]["unresolved_issues"]
    assert_equal "GS", apps["storefront"]["issue_prefix"]
    assert_equal %w[production staging], apps["storefront"]["environments"]
    assert_match "storefront (storefront, rails, prefix GS): 3 unresolved", mcp_text(result)
    assert_no_secrets result
  end

  test "list_apps never shows another account's apps" do
    assert_equal %w[umbrella-app], structured(mcp_tool(:outsider_read, "list_apps"))["apps"].map { it["slug"] }
  end

  # ── search_issues ────────────────────────────────────────────

  test "search_issues uses the issue list's query syntax and sort" do
    result = mcp_tool(:philip_read, "search_issues", query: "is:unresolved env:staging")

    assert_untrusted_notice result
    assert_equal %w[GS-1038], structured(result)["issues"].map { it["short_id"] }
    row = structured(result)["issues"].first
    assert_equal "storefront", row["app"]
    assert_match %r{/projects/storefront/issues/GS-1038\z}, row["url"]

    events = structured(mcp_tool(:philip_read, "search_issues", sort: "events"))["issues"].map { it["events"] }
    assert_equal events.sort.reverse, events
  end

  test "search_issues defaults to unresolved across all apps and narrows by app, text and range" do
    all = structured(mcp_tool(:philip_read, "search_issues"))["issues"].map { it["short_id"] }
    assert_includes all, "BA-#{issues(:billing_timeout).number}" if issues(:billing_timeout).unresolved?
    assert_not_includes all, "GS-1020"

    by_app = structured(mcp_tool(:philip_read, "search_issues", app: "billing-api", query: "is:resolved is:unresolved"))
    assert by_app["issues"].all? { it["app"] == "billing-api" }

    assert_equal %w[GS-1042], structured(mcp_tool(:philip_read, "search_issues", query: "price_cents"))["issues"].map { it["short_id"] }
    recent = structured(mcp_tool(:philip_read, "search_issues", range: "1h"))["issues"]
    assert recent.all? { Time.zone.parse(it["last_seen_at"]) >= 1.hour.ago }
  end

  test "search_issues pages with a cursor" do
    first = structured(mcp_tool(:philip_read, "search_issues", query: "", limit: 1, app: "storefront"))
    assert_equal 1, first["issues"].size
    assert first["next_cursor"]

    second = structured(mcp_tool(:philip_read, "search_issues", query: "", limit: 1, app: "storefront", cursor: first["next_cursor"]))
    assert_not_equal first["issues"].first["short_id"], second["issues"].first["short_id"]

    assert_tool_error mcp_tool(:philip_read, "search_issues", cursor: "bogus!"), /Invalid cursor/
  end

  test "search_issues: unknown and other-account apps are not found" do
    assert_tool_error mcp_tool(:philip_read, "search_issues", app: "nope"), /No app with the slug "nope"/
    assert_tool_error mcp_tool(:philip_read, "search_issues", app: "umbrella-app"), /No app with the slug "umbrella-app"/
  end

  # ── get_issue ────────────────────────────────────────────────

  test "get_issue returns the summary, trend, tags and the latest occurrence's backtrace and breadcrumbs" do
    result = mcp_tool(:philip_read, "get_issue", issue: "gs-1042")
    issue = structured(result)

    assert_untrusted_notice result
    assert_equal "GS-1042", issue["short_id"]
    assert_equal "Philip Nguyen", issue["assignee"]
    assert_equal 24, issue.dig("trend", "hourly_24h", "counts").size
    assert_equal 30, issue.dig("trend", "daily_30d", "counts").size
    assert_equal %w[a1b2c3d], issue["releases"].map { it["release"] }
    assert_includes issue["tags"].map { it["key"] }, "browser"
    assert_equal "note", issue["recent_activity"].first["kind"]

    frames = issue.dig("latest_occurrence", "backtrace")
    assert_equal [ true, true, true, false ], frames.first(4).map { it["in_app"] }, "app frames first"
    assert_equal "app/services/cart_total.rb", frames.first["file"]
    assert(frames.first["code"].any? { it["error"] && it["text"].include?("price_cents") })
    assert_equal 4, issue.dig("latest_occurrence", "breadcrumbs").size
    assert_match "→ app/services/cart_total.rb:42 in line_total", mcp_text(result)
  end

  test "get_issue finds issues by numeric id too" do
    assert_equal "GS-1042", structured(mcp_tool(:philip_read, "get_issue", issue: issues(:nomethod).id))["short_id"]
    assert_equal "GS-1042", structured(mcp_tool(:philip_read, "get_issue", issue: issues(:nomethod).id.to_s))["short_id"]
  end

  test "get_issue: unknown, malformed and other-account issues are all simply not found" do
    [ "GS-9999", "ZZ-1", "banana", issues(:umbrella_issue).id, "UA-#{issues(:umbrella_issue).number}" ].each do |reference|
      assert_tool_error mcp_tool(:philip_read, "get_issue", issue: reference), /Issue not found/
    end
  end

  test "without request_data the message is redacted and locals are left out" do
    result = mcp_tool(:philip_read, "get_issue", issue: "GS-1042")
    occurrence = structured(result)["latest_occurrence"]

    assert_match "[email]", occurrence["message"]
    assert occurrence["backtrace"].none? { it.key?("locals") }
    PERSONAL.each { |value| assert_not_includes result.to_json, value }
  end

  # ── list_occurrences ─────────────────────────────────────────

  test "list_occurrences lists stored occurrences newest first with host and transaction, paged" do
    result = mcp_tool(:philip_read, "list_occurrences", issue: "GS-1042", limit: 1)
    page = structured(result)

    assert_untrusted_notice result
    assert_equal [ occurrences(:nomethod_latest).uuid ], page["occurrences"].map { it["id"] }
    assert_equal "web-7f9c-2", page["occurrences"].first["host"]
    assert_equal "CheckoutsController#create", page["occurrences"].first["transaction"]

    following = structured(mcp_tool(:philip_read, "list_occurrences", issue: "GS-1042", limit: 1, cursor: page["next_cursor"]))
    assert_equal [ occurrences(:nomethod_oldest).uuid ], following["occurrences"].map { it["id"] }
    assert_nil following["next_cursor"]
  end

  test "list_occurrences: other-account issues are not found" do
    assert_tool_error mcp_tool(:philip_read, "list_occurrences", issue: issues(:umbrella_issue).id), /Issue not found/
  end

  # ── get_occurrence ───────────────────────────────────────────

  test "get_occurrence without request_data omits personal data and says which scope adds it" do
    result = mcp_tool(:philip_read, "get_occurrence", occurrence: occurrences(:nomethod_latest).uuid)
    occurrence = structured(result)

    assert_untrusted_notice result
    assert_equal "GS-1042", occurrence["issue"]
    assert_equal "web-7f9c-2", occurrence.dig("environment_context", "host")
    assert_includes occurrence["omitted"], "params"
    assert_match "request_data scope", occurrence["omitted_note"]
    assert_match "request_data scope", mcp_text(result)
    %w[request params headers session user].each { |key| assert_not occurrence.key?(key) }
    PERSONAL.each { |value| assert_not_includes result.to_json, value }
  end

  test "get_occurrence with request_data includes request, params, headers, session, user and locals" do
    result = mcp_tool(:philip_full, "get_occurrence", occurrence: occurrences(:nomethod_latest).uuid)
    occurrence = structured(result)

    assert_equal "FALL25", occurrence.dig("params", "coupon")
    assert_equal "[FILTERED]", occurrence.dig("params", "card_token"), "scrubbed at ingest, still scrubbed"
    assert_equal "Mara Lindqvist", occurrence.dig("user", "name")
    assert_equal "POST", occurrence.dig("request", "method")
    assert occurrence["headers"].key?("User-Agent")
    assert_match "mara@example.com", occurrence["message"]
    assert occurrence["backtrace"].first.key?("locals")
    assert_nil occurrence["omitted"]
    assert_untrusted_notice result
  end

  test "get_occurrence shows job details, with arguments only for request_data" do
    uuid = occurrences(:regressed_latest).uuid

    job = structured(mcp_tool(:philip_read, "get_occurrence", occurrence: uuid))["job"]
    assert_equal "Orders::PlaceJob", job["class"]
    assert_nil job["arguments"]

    assert structured(mcp_tool(:philip_full, "get_occurrence", occurrence: uuid))["job"]["arguments"].present?
  end

  test "get_occurrence: unknown and other-account occurrences are not found" do
    [ occurrences(:umbrella_occurrence).uuid, SecureRandom.uuid, "not-a-uuid" ].each do |id|
      assert_tool_error mcp_tool(:philip_full, "get_occurrence", occurrence: id), /Occurrence not found/
    end
  end

  # ── get_uptime ───────────────────────────────────────────────

  test "get_uptime shows monitors with hosts, never URLs" do
    result = mcp_tool(:philip_read, "get_uptime")
    monitors = structured(result)["monitors"].index_by { it["name"] }

    assert_equal "storefront.example", monitors["Storefront home"]["host"]
    assert_equal "down", monitors["Storefront API"]["status"]
    assert_equal "HTTP 503", monitors["Storefront API"].dig("open_incident", "cause")
    assert_equal %w[24h 7d 30d], monitors["Storefront home"]["uptime_percent"].keys
    assert_not monitors.key?("Umbrella site")
    assert_not_includes result.to_json, "https://"
    assert_no_secrets result
  end

  test "get_uptime narrows to one app; other-account apps are not found" do
    assert_equal [ "billing-api" ], structured(mcp_tool(:philip_read, "get_uptime", app: "billing-api"))["monitors"].map { it["app"] }.uniq
    assert_tool_error mcp_tool(:philip_read, "get_uptime", app: "umbrella-app"), /No app/
  end

  # ── get_performance ──────────────────────────────────────────

  test "get_performance returns totals and transactions with flags and the slowest trace" do
    result = mcp_tool(:philip_read, "get_performance", app: "storefront")
    performance = structured(result)

    assert_equal "production", performance["environment"]
    assert_equal "1d", performance["range"]
    assert_equal %w[rate average p75 p90 p95 p99 failed], performance["totals"].keys
    checkout = performance["transactions"].find { it["name"] == "CheckoutsController#create" }
    assert checkout["n_plus_one"]
    assert_equal apm_traces(:checkout_slow).uuid, checkout["slowest_trace"]
    assert checkout["p95_ms"].positive?
    assert_not_includes result.to_json, "apm-fixture-secret"

    failed_rate = Apm::Overview.new(projects(:storefront), Apm::Selection.new(projects(:storefront), {}, entitlements: accounts(:acme).entitlements)).tiles.last.value
    assert failed_rate.positive?
    assert_equal failed_rate.round(4), performance["totals"]["failed"], "a fraction, not rounded away"
    assert_match "failed #{Mcp::Text.percent(failed_rate.round(4))}", mcp_text(result)
  end

  test "get_performance shows jobs, and refuses locked ranges and unknown environments" do
    jobs = structured(mcp_tool(:philip_read, "get_performance", app: "storefront", kind: "job"))
    assert_equal [ "Orders::PlaceJob" ], jobs["transactions"].map { it["name"] }

    with_hosted_mode do
      accounts(:acme).update_entitlements!("apm_retention_days" => 1)
      assert_tool_error mcp_tool(:philip_read, "get_performance", app: "storefront", range: "7d"), /isn't available/
    end
    assert_tool_error mcp_tool(:philip_read, "get_performance", app: "storefront", environment: "moon"), /No performance data/
    assert_tool_error mcp_tool(:philip_read, "get_performance", app: "umbrella-app"), /No app/
  end

  # ── get_trace ────────────────────────────────────────────────

  test "get_trace returns layers, spans and N+1 groups with call site and code" do
    result = mcp_tool(:philip_read, "get_trace", trace: apm_traces(:checkout_slow).uuid)
    trace = structured(result)

    assert_untrusted_notice result
    assert_equal "POST /checkout", trace["title"]
    assert_equal %w[db http view ruby], trace["layers"].map { it["layer"] }
    group = trace["n_plus_one"].first
    assert_equal 38, group["calls"]
    assert_equal "app/services/cart_total.rb", group.dig("call_site", "file")
    assert group.dig("call_site", "code").any?
    assert_match "includes(:product)", group["hint"]
  end

  test "get_trace: past the retention it says the trace is no longer kept" do
    with_hosted_mode do
      accounts(:acme).update_entitlements!("apm_retention_days" => 1)
      travel 2.days do
        assert_tool_error mcp_tool(:philip_read, "get_trace", trace: apm_traces(:checkout_slow).uuid), /no longer kept/
      end
    end
  end

  test "get_trace: other-account and unknown traces are not found" do
    assert_tool_error mcp_tool(:philip_read, "get_trace", trace: apm_traces(:umbrella_trace).uuid), /no longer kept|not found/i
    assert_tool_error mcp_tool(:philip_read, "get_trace", trace: SecureRandom.uuid), /Trace not found/
    assert_tool_error mcp_tool(:philip_read, "get_trace", trace: "nope"), /Trace not found/
  end

  # ── triage ───────────────────────────────────────────────────

  test "resolve_issue resolves through Issue::Triage, marks the activity via MCP, audits and broadcasts" do
    assert_enqueued_with(job: BroadcastProjectChangesJob) do
      result = mcp_tool(:philip_triage, "resolve_issue", issues: [ "GS-1042", "GS-1020" ])
      assert_equal({ "GS-1042" => "resolved", "GS-1020" => "resolved" }, structured(result)["issues"].to_h { [ it["short_id"], it["status"] ] })
      assert_equal 1, structured(result)["changed"]
    end

    assert issues(:nomethod).reload.resolved?
    activity = issues(:nomethod).activities.recent.first
    assert_equal [ "resolved", "mcp", users(:philip).id ], [ activity.kind, activity.via, activity.user_id ]
    audit = AccessTokenActivity.order(:id).last
    assert_equal [ personal_access_tokens(:philip_triage).id, users(:philip).id, "resolve", [ issues(:nomethod).id ] ],
                 [ audit.personal_access_token_id, audit.user_id, audit.action, audit.issue_ids ]
  end

  test "ignore_issue and unresolve_issue change status and are audited" do
    mcp_tool(:philip_triage, "ignore_issue", issues: [ "GS-1001" ])
    assert issues(:card_error).reload.ignored?

    result = mcp_tool(:philip_triage, "unresolve_issue", issues: [ "GS-1001", "GS-1020" ])
    assert_equal %w[unresolved unresolved], structured(result)["issues"].map { it["status"] }
    assert_equal %w[ignore unresolve], AccessTokenActivity.order(:id).last(2).map(&:action)
  end

  test "triage with any unknown or other-account id changes nothing" do
    assert_no_difference -> { AccessTokenActivity.count } do
      result = mcp_tool(:philip_triage, "resolve_issue", issues: [ "GS-1042", issues(:umbrella_issue).id ])
      assert_tool_error result, /Issue not found/
    end
    assert issues(:nomethod).reload.unresolved?
    assert issues(:umbrella_issue).reload.unresolved?
  end

  test "triage takes at most 25 issues" do
    assert mcp_tool(:philip_triage, "resolve_issue", issues: Array.new(26) { "GS-1042" })["isError"]
  end

  test "add_note adds a note as the token's user via MCP and audits it without the text" do
    result = mcp_tool(:philip_triage, "add_note", issue: "GS-1042", body: "Investigated from Claude Code")

    note = issues(:nomethod).activities.note.recent.first
    assert_equal [ "Investigated from Claude Code", users(:philip), "mcp" ], [ note.body, note.user, note.via ]
    assert_equal "GS-1042", structured(result)["issue"]
    assert_equal [ "note", [ issues(:nomethod).id ] ], AccessTokenActivity.order(:id).last.then { [ it.action, it.issue_ids ] }
  end

  test "add_note refuses notes over 2,000 characters and other-account issues" do
    assert mcp_tool(:philip_triage, "add_note", issue: "GS-1042", body: "x" * 2_001)["isError"]
    assert_tool_error mcp_tool(:philip_triage, "add_note", issue: issues(:umbrella_issue).id, body: "hi"), /Issue not found/
  end

  # ── performance and size ─────────────────────────────────────

  test "each read tool runs a fixed number of queries however much data there is" do
    calls = {
      "list_apps" => {}, "search_issues" => { query: "" }, "get_issue" => { issue: "GS-1042" },
      "list_occurrences" => { issue: "GS-1042" }, "get_uptime" => {}
    }
    mcp_tool(:philip_read, "list_apps") # the first call of a while records the token's use
    baseline = calls.to_h { |name, arguments| [ name, count_queries { mcp_tool(:philip_read, name, **arguments) } ] }

    add_more_data
    calls.each do |name, arguments|
      assert_equal baseline[name], count_queries { mcp_tool(:philip_read, name, **arguments) }, name
    end
  end

  test "responses stay small" do
    %w[list_apps get_uptime].each { assert_operator response_size("tools/call", name: it, arguments: {}), :<, 50_000 }
    assert_operator response_size("tools/call", name: "get_issue", arguments: { issue: "GS-1042" }, token: :philip_full), :<, 50_000
  end

  private
    def count_queries(&)
      queries = []
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
      queries.size
    end

    def response_size(method, token: :philip_read, **params)
      mcp_request(method, params, token:)
      response.body.bytesize
    end

    def add_more_data
      project = projects(:storefront)
      3.times do |n|
        issue = project.issues.create!(number: 2000 + n, fingerprint: SecureRandom.hex(32), exception_class: "Extra#{n}Error",
                                       message: "extra", first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago, environments: [ "production" ])
        issue.activities.note.create!(body: "note #{n}", user: users(:jo))
      end
      issues(:nomethod).occurrences.create!(occurrences(:nomethod_latest).attributes.except("id", "uuid", "created_at").merge(uuid: SecureRandom.uuid))
      project.uptime_monitors.create!(name: "Extra", url: "https://extra.example/up", interval_minutes: 10)
      accounts(:acme).projects.create!(name: "extra app")
    end
end
