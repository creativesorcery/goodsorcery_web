require "test_helper"
require_relative "../../../test_helpers/performance_pages_test_helper"

class Projects::Performance::OverviewsControllerTest < ActionDispatch::IntegrationTest
  include ApmFixtureClock

  include PerformancePagesTestHelper

  setup do
    @project = projects(:storefront)
    sign_in_as users(:alex)
  end

  test "the tiles are Requests per minute, Average, p75, p90, p95, p99 and Failed, each with a Last hour subline" do
    get project_performance_path(@project)

    assert_response :success
    assert_select "h1", /Performance\s*— last 24 hours/
    assert_select ".eyebrow", "storefront · production"
    labels = css_select("section[aria-label=Summary] [data-tile] > div:first-child").map { it.text.strip }
    assert_equal [ "Requests per minute", "Average", "p75", "p90", "p95", "p99", "Failed requests" ], labels
    assert_select "[data-tile=p50]", count: 0
    assert_select "[data-tile]" do |tiles|
      tiles.each { |tile| assert_match(/Last hour/, tile.text) }
    end
    assert_select "[data-tile=failed] a[href=?]", project_issues_path(@project, env: "production"), text: "see issues"
  end

  test "the p95 subline is coral with the rise in percent only when the total is Slower" do
    get project_performance_path(@project)

    assert_select "[data-tile=p95] .text-coral-300", /Last hour .+ · ▲ \d+%/
    assert_select "[data-tile=p99] .text-coral-300", count: 0
    assert_select "[data-tile=p95] .coral-dot"

    get project_performance_path(@project, tab: "jobs")

    assert_select "[data-tile=p95] .text-coral-300", count: 0
    assert_select "[data-tile=p95]", /Last hour \d/
  end

  test "the chart shows the layers and the p95 line every 15 minutes" do
    get project_performance_path(@project)

    assert_select "h2", "Where request time goes"
    assert_select "p", "Average time per request by layer, every 15 minutes. The line is p95."
    assert_select "svg[role=img][aria-label^='Average time per request by layer']" do
      assert_select "g > title", minimum: 1
      assert_select "path[stroke='#{PerformanceChartHelper::CORAL}']", 1
    end
    assert_select "span", "−24h"
  end

  test "the web table shows p75, p90, p95 and p99 and sorts by time consumed with Slower and N+1 chips" do
    get project_performance_path(@project)

    headers = css_select("section[aria-label=Endpoints] .uppercase > span").map { it.text.strip }
    assert_equal [ "Endpoint", "Req/min", "p75", "p90", "p95", "p99", "Failed", "Time share", "p95 · 24h" ], headers
    names = css_select("section[aria-label=Endpoints] a.font-mono").map(&:text)
    assert_equal [ "CheckoutsController#create", "ProductsController#show" ], names
    checkout = transaction_row("CheckoutsController#create")
    assert_select checkout, ".chip-coral", "Slower"
    assert_select checkout, ".chip-lilac", "N+1 queries"
    assert_select checkout, ".font-mono", "POST /checkout"
    assert_select checkout, "svg path[stroke='#{ChartHelper::CORAL}']"
    products = transaction_row("ProductsController#show")
    assert_select products, ".chip", count: 0
    assert_select products, "svg path[stroke='#{ChartHelper::IRIS}']"
    assert_select "a[href=?]", project_performance_transaction_path(@project, apm_transactions(:checkout_create), env: "production", range: "1d")
    assert_select "p", /Showing 2 of 2 endpoints/
    assert_select "a", text: "show all", count: 0
  end

  test "tabs count transactions with data and the jobs tab shows runs, queue and queue wait" do
    get project_performance_path(@project)
    assert_select "a.tab[aria-selected=true]", /Web requests\s*2/
    assert_select "a.tab[aria-selected=false]", /Background jobs\s*1/

    get project_performance_path(@project, tab: "jobs", range: "1d", env: "production")

    assert_select "a.tab[aria-selected=true]", /Background jobs\s*1/
    assert_select "[data-tile=rate] div", "Runs per minute"
    assert_select "[data-tile=failed] div", "Failed runs"
    assert_select "h2", "Where job time goes"
    assert_select ".uppercase > span", "Job"
    assert_select ".uppercase > span", "Runs/min"
    row = transaction_row("Orders::PlaceJob")
    assert_select row, ".font-mono", /\Asidekiq · critical · waits .+ \(p95\)\z/
    assert_select "input[placeholder='Filter jobs']"
  end

  test "the filter narrows the rows by name or route and keeps env, range and tab" do
    get project_performance_path(@project, q: "products/")

    assert_select "section[aria-label=Endpoints] a.font-mono", 1
    assert_select "section[aria-label=Endpoints] a.font-mono", "ProductsController#show"
    assert_select "form[role=search] input[type=hidden][name=env][value=production]"
    assert_select "form[role=search] input[type=hidden][name=range][value='1d']"
    assert_select "form[role=search] input[type=hidden][name=tab][value=web]"
    assert_select "input[name=q][value='products/']"

    get project_performance_path(@project, q: "nothing-like-this")
    assert_select "p", /No endpoints match “nothing-like-this”/
  end

  test "sorting by rate puts the busiest endpoint first" do
    get project_performance_path(@project, sort: "rate")

    assert_equal "ProductsController#show", css_select("section[aria-label=Endpoints] a.font-mono").first.text
    assert_select "button", /Sort: Most requests/

    get project_performance_path(@project, sort: "p95")
    assert_equal "CheckoutsController#create", css_select("section[aria-label=Endpoints] a.font-mono").first.text
  end

  test "more than 25 rows show 25 and a show all link" do
    project = projects(:billing)
    25.times { |i| create_apm_transaction(project, "Extra#{i}Controller#index") }

    get project_performance_path(project)
    assert_select "section[aria-label=Endpoints] a.font-mono", 25
    assert_select "p", /Showing 25 of 26 endpoints/
    assert_select "a[href=?]", project_performance_path(project, env: "production", range: "1d", tab: "web", all: "1"), text: "show all"

    get project_performance_path(project, all: "1")
    assert_select "section[aria-label=Endpoints] a.font-mono", 26
  end

  test "the environment menu lists environments with data and env picks one" do
    create_apm_transaction(@project, "HomeController#index", environment: "staging")

    get project_performance_path(@project)
    assert_select "[data-apm-environments] .menu a", 2
    assert_select ".menu a[href=?]", project_performance_path(@project, env: "staging", range: "1d", tab: "web"), text: /staging/

    get project_performance_path(@project, env: "staging")
    assert_select ".eyebrow", "storefront · staging"
    assert_select "section[aria-label=Endpoints] a.font-mono", "HomeController#index"

    get project_performance_path(@project, env: "nowhere")
    assert_select ".eyebrow", "storefront · production"
  end

  test "an app without performance data shows the empty state with the gem snippet" do
    get project_performance_path(projects(:marketing))

    assert_response :success
    assert_select "h2", "See where request time goes"
    assert_select "p", /Turn on performance monitoring in the goodsorcery gem/
    assert_select "pre", "config.performance_monitoring = true"
    assert_select "a[href=?]", project_setup_path(projects(:marketing)), text: "Settings & setup"
    assert_select ".code-pane-header", "config/initializers/goodsorcery.rb"
  end

  test "the empty state follows the app's platform" do
    projects(:marketing).update!(platform: "ruby")
    get project_performance_path(projects(:marketing))
    assert_select ".code-pane-header", "config/goodsorcery.rb"

    projects(:marketing).update!(platform: "rust")
    get project_performance_path(projects(:marketing))
    assert_select "p", /Turn on performance monitoring in the goodsorcery crate/
    assert_select ".code-pane-header", "src/main.rs"
    assert_select "pre", "goodsorcery::Config::from_env().performance_monitoring(true)"
    assert_select "p", /\.layer\(goodsorcery::axum::layer\(\)\)/
    assert_select "pre", text: /config\.performance_monitoring/, count: 0
  end

  test "self-hosted shows every range and no upgrade copy" do
    get project_performance_path(@project, range: "7d")

    assert_select "h1", /last 7 days/
    assert_select "nav[aria-label='Time range'] a", 5
    assert_select "nav[aria-label='Time range'] a[aria-current=true]", "7d"
    assert_no_match "Upgrade to unlock", response.body
  end

  test "hosted with a day of retention locks 7d and 30d and a crafted 7d falls back to 1d" do
    with_hosted_mode do
      with_upgrade_url("https://billing.example/upgrade") do
        get project_performance_path(@project, range: "7d")
      end
    end

    assert_select "h1", /last 24 hours/
    assert_select "nav[aria-label='Time range'] a", 3
    assert_select "nav[aria-label='Time range'] span[aria-disabled=true][title='Upgrade to unlock']", 2
    assert_select "nav[aria-label='Time range'] span[aria-label='7 days, upgrade to unlock'] svg", 1
    assert_select "a[href='https://billing.example/upgrade']", "Upgrade to unlock"
  end

  test "hosted without an upgrade URL, 7d and 30d are greyed out and say Coming soon on hover" do
    with_hosted_mode { with_upgrade_url(nil) { get project_performance_path(@project) } }

    assert_select "nav[aria-label='Time range'] a", 3
    assert_select "nav[aria-label='Time range'] span.opacity-50.cursor-not-allowed[aria-disabled=true][title='Coming soon']", 2
    assert_select "nav[aria-label='Time range'] span[title='Coming soon']", text: "7d"
    assert_select "nav[aria-label='Time range'] span[aria-label='30 days, coming soon']", text: "30d"
    assert_select "nav[aria-label='Time range'] span[title='Coming soon'] svg", 0
    assert_select ".touch-hint[aria-hidden=true]", "7d and 30d: coming soon."
    assert_no_match "Upgrade", response.body
  end

  test "the upgrade link is the only reason given when an upgrade URL is set" do
    with_hosted_mode { with_upgrade_url("https://billing.example/upgrade") { get project_performance_path(@project) } }

    assert_select "a[href='https://billing.example/upgrade']", "Upgrade to unlock"
    assert_select ".touch-hint", 0
  end

  test "self-hosted with a short performance retention says how many days it keeps, for touch screens" do
    Rails.configuration.x.apm_retention_days, previous = 3, Rails.configuration.x.apm_retention_days
    get project_performance_path(@project)

    assert_select "nav[aria-label='Time range'] span[aria-disabled=true][title='This instance keeps 3 days']", 2
    assert_select ".touch-hint", "This instance keeps 3 days."
  ensure
    Rails.configuration.x.apm_retention_days = previous if previous
  end

  test "nothing locked, no hint" do
    get project_performance_path(@project)
    assert_select ".touch-hint", 0
  end

  test "the per-transaction figures are cached as numbers only" do
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    get project_performance_path(@project)

    key = [ "apm_overview", Apm::Figures.members.size, @project.id, "production", *Apm::Range.pick("1d", entitlements: accounts(:acme).entitlements).cache_key ]
    cached = Rails.cache.read(key)
    assert_kind_of Hash, cached
    assert_includes cached.keys, apm_transactions(:checkout_create).id
    assert cached.all? { |id, values| id.is_a?(Integer) && values.all? { it.nil? || it.is_a?(Numeric) } }
  ensure
    Rails.cache = previous
  end

  test "the overview costs the same number of statements for 1 or 5 transactions" do
    project = projects(:billing)
    one = request_statements { get project_performance_path(project) }
    4.times { |i| create_apm_transaction(project, "More#{i}Controller#show") }
    five = request_statements { get project_performance_path(project) }

    assert_select "section[aria-label=Endpoints] a.font-mono", 5
    assert_equal one.size, five.size, -> { "Only with 5:\n#{(five - one).join("\n")}\nOnly with 1:\n#{(one - five).join("\n")}" }
  end

  test "sends no-store, has no inline styles and never shows trace data" do
    get project_performance_path(@project)

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_match(/style="/, response.body)
    assert_no_match SECRET, response.body
  end

  test "the sidebar links to Performance after Issues" do
    get project_performance_path(@project)

    links = css_select("aside nav[aria-label=Main] a.nav-link").map { it.text.squish }
    issues = links.index { it.start_with?("Issues") }
    assert_equal "Performance", links[issues + 1]
    assert_select "aside a.nav-link[aria-current=page][href=?]", project_performance_path(@project)
  end

  test "another account's app is a 404 and signed-out visitors go to sign in" do
    get project_performance_path(projects(:umbrella_app))
    assert_response :not_found

    sign_out
    get project_performance_path(@project)
    assert_redirected_to new_session_path

    sign_in_as users(:outsider)
    get project_performance_path(@project)
    assert_response :not_found
  end

  private
    def transaction_row(name)
      css_select("[data-apm-table] .group").find { |row| row.at_css("a.font-mono")&.text == name }.tap { assert it, "no row for #{name}" }
    end
end
