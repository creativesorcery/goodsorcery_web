require "test_helper"
require_relative "../../test_helpers/uptime_test_helper"

class Projects::UptimeMonitorsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier, UptimeTestHelper

  setup do
    @project = projects(:storefront)
    @monitor = uptime_monitors(:storefront_home)
    sign_in_as users(:philip)
  end

  # --- index ---

  test "index lists the app's monitors with status, host, interval, response and uptime" do
    get project_uptime_monitors_path(@project)

    assert_response :success
    assert_select "h1", /Uptime\s*— 2 monitors/
    assert_select "aside a.nav-link[aria-current=page][href=?]", project_uptime_monitors_path(@project)
    assert_select "turbo-frame##{dom_id(@monitor, :row)}[target=_top]" do
      assert_select ".chip-mint", "Up"
      assert_select "a[href=?]", project_uptime_monitor_path(@project, @monitor), text: "Storefront home"
      assert_select ".font-mono", "storefront.example"
      assert_select "span", "Every 10 minutes"
      assert_select "span", "212 ms"
      assert_select "svg[role=img] rect", 24
    end
    assert_select "turbo-frame##{dom_id(uptime_monitors(:storefront_api), :row)} .chip-coral", /Down for 12 min/
    assert_select "turbo-frame##{dom_id(uptime_monitors(:billing_checkout), :row)}", count: 0
    assert_select "a[href=?]", new_project_uptime_monitor_path(@project), text: /Add a monitor/
    assert_select "turbo-cable-stream-source[channel=AuthorizedStreamsChannel]"
  end

  test "index never shows a monitor's path or query, sends no-store and has no inline styles" do
    get project_uptime_monitors_path(@project)

    assert_no_match SECRET, response.body
    assert_no_match "/up?token", response.body
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_match(/style="/, response.body)
  end

  test "index costs the same number of queries for 1 or 5 monitors" do
    project = projects(:billing)
    one = count_request_queries { get project_uptime_monitors_path(project) }

    4.times { |i| project.uptime_monitors.create!(name: "Extra #{i}", url: "https://extra#{i}.example/") }
    five = count_request_queries { get project_uptime_monitors_path(project) }

    assert_select "h1", /5 monitors/
    assert_equal one, five
  end

  test "an app without monitors shows the empty state" do
    get project_uptime_monitors_path(projects(:marketing))

    assert_response :success
    assert_select "h2", "Watch your app from the outside"
    assert_select "p", /emails you when it stops answering and again when it's back/
    assert_select "a[href=?]", new_project_uptime_monitor_path(projects(:marketing)), text: /Add a monitor/
    assert_no_match "Upgrade to unlock", response.body
  end

  test "hosted at the limit, the add button becomes a limit chip with the upgrade link" do
    with_hosted_mode do
      with_upgrade_url("https://billing.example/upgrade") do
        get project_uptime_monitors_path(@project)
      end
    end

    assert_select "a[href=?]", new_project_uptime_monitor_path(@project), count: 0
    assert_select ".chip", "3 of 1 monitor used", "acme counts the monitors of all its apps"
    assert_select "a[href=?][target=_blank]", "https://billing.example/upgrade", text: "Upgrade to unlock"
  end

  test "hosted with a limit of zero, the empty state offers the upgrade instead of the form" do
    accounts(:acme).update!(entitlement_values: { "max_monitors" => 0 })

    with_hosted_mode { with_upgrade_url { get project_uptime_monitors_path(projects(:marketing)) } }

    assert_select "h2", "Watch your app from the outside"
    assert_select "a[href=?]", new_project_uptime_monitor_path(projects(:marketing)), count: 0
    assert_select "a[href=?]", "https://billing.example/upgrade", text: "Upgrade to unlock"
    assert_select ".chip", count: 0

    with_hosted_mode { with_upgrade_url { get new_project_uptime_monitor_path(projects(:marketing)) } }
    assert_select "#uptime_monitor_limit h2", "Uptime monitors aren't included in this account."
  end

  test "hosted at the limit without an upgrade URL, the add button says more are coming soon" do
    with_hosted_mode { with_upgrade_url(nil) { get project_uptime_monitors_path(@project) } }

    assert_select "a[href=?]", new_project_uptime_monitor_path(@project), count: 0
    assert_select "span[aria-disabled=true][title='Coming soon']", text: "Cannot add more yet, but it's coming soon"
    assert_select ".chip", text: /monitor used/, count: 0
    assert_no_match "Upgrade", response.body
  end

  test "hosted with a limit of zero and no upgrade URL, the empty state says coming soon" do
    accounts(:acme).update!(entitlement_values: { "max_monitors" => 0 })

    with_hosted_mode { with_upgrade_url(nil) { get project_uptime_monitors_path(projects(:marketing)) } }

    assert_select "h2", "Watch your app from the outside"
    assert_select "a[href=?]", new_project_uptime_monitor_path(projects(:marketing)), count: 0
    assert_select "span[aria-disabled=true]", "Cannot add more yet, but it's coming soon"
    assert_no_match "Upgrade", response.body
  end

  test "hosted, a paused monitor says it is over the limit" do
    @monitor.update_columns(paused_at: Time.current)

    with_hosted_mode { with_upgrade_url { get project_uptime_monitors_path(@project) } }

    assert_select "turbo-frame##{dom_id(@monitor, :row)}" do
      assert_select ".chip-muted", "Paused"
      assert_select "p", /Over this account's monitor limit\.\s*Upgrade to unlock/
    end
  end

  test "hosted without an upgrade URL, a paused monitor's note has no upgrade text" do
    @monitor.update_columns(paused_at: Time.current)

    with_hosted_mode { with_upgrade_url(nil) { get project_uptime_monitor_path(@project, @monitor) } }

    assert_select "p", "Over this account's monitor limit."
    assert_no_match "Upgrade", response.body
  end

  test "self-hosted never shows locked options or the upgrade text" do
    @monitor.update_columns(paused_at: Time.current)

    [ project_uptime_monitors_path(@project), new_project_uptime_monitor_path(@project),
      project_uptime_monitor_path(@project, @monitor) ].each do |path|
      get path
      assert_response :success
      assert_no_match "Upgrade to unlock", response.body
      assert_select "option[disabled]", count: 0
    end
  end

  test "self-hosted, a monitor paused while hosted says how to resume it" do
    @monitor.update_columns(paused_at: Time.current)

    get project_uptime_monitor_path(@project, @monitor)

    assert_select "p", /Paused while this instance was hosted\. Run\s+bin\/rails goodsorcery:fit_uptime_monitors\s+to resume it\./
    assert_select "dt", "Paused since"
  end

  test "a monitor never checked shows no up-since and no every-check claim" do
    monitor = projects(:storefront).uptime_monitors.create!(name: "Fresh", url: "https://fresh.example/")

    get project_uptime_monitor_path(@project, monitor)

    assert_select "dd", "Not checked yet"
    assert_select "dt", text: "Up since", count: 0
    assert_select "p", "No incidents yet."
  end

  test "the interval select is labelled Check interval and tied to its hint when intervals are locked" do
    accounts(:acme).update!(entitlement_values: { "max_monitors" => 10 })
    with_hosted_mode { with_upgrade_url { get new_project_uptime_monitor_path(projects(:marketing)) } }
    assert_response :success

    assert_select "label[for=uptime_monitor_interval_minutes]", "Check interval"
    assert_select "select#uptime_monitor_interval_minutes[aria-describedby=uptime_monitor_interval_hint]"
    assert_select "p#uptime_monitor_interval_hint", /Upgrade to unlock/
  end

  # --- show ---

  test "show has the full URL, the ribbon, the 30-day bar, incidents and recent checks" do
    get project_uptime_monitor_path(@project, @monitor)

    assert_response :success
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_select "turbo-frame##{dom_id(@monitor, :report)}[target=_top]" do
      assert_select "h1", "Storefront home"
      assert_select "p.font-mono", "https://storefront.example/up?token=uptime-fixture-secret"
      assert_select "form[action=?] button", project_uptime_monitor_check_path(@project, @monitor), text: "Check now"
      assert_select "a[href=?]", edit_project_uptime_monitor_path(@project, @monitor), text: "Edit"
      assert_select "form[action=?] button[data-turbo-confirm=?]", project_uptime_monitor_path(@project, @monitor),
        "Delete Storefront home? Its check history goes too."
      assert_select "dt", "Uptime 24h"
      assert_select "dt", "Up since"
      assert_select "section[aria-labelledby=uptime_days_heading] svg rect", 30
      assert_select "##{dom_id(uptime_incidents(:storefront_home_timeout))}", /Timed out after 10 s/
      assert_select "section[aria-labelledby=uptime_checks_heading] li", 6
    end
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_match(/style="/, response.body)
  end

  test "show for a down monitor marks the open incident as ongoing" do
    monitor = uptime_monitors(:storefront_api)

    get project_uptime_monitor_path(@project, monitor)

    assert_select "dt", "Down since"
    assert_select "##{dom_id(uptime_incidents(:storefront_api_outage))}" do
      assert_select ".text-coral-300", /ongoing/
      assert_select "div", /HTTP 503/
    end
  end

  test "show for a pending monitor without checks yet" do
    get project_uptime_monitor_path(projects(:billing), uptime_monitors(:billing_checkout))

    assert_response :success
    assert_select ".chip-muted", "Pending"
    assert_select "p", /No checks yet/
    assert_select "p", /No incidents/
  end

  test "a paused monitor has no Check now button" do
    @monitor.update_columns(paused_at: Time.current)

    get project_uptime_monitor_path(@project, @monitor)

    assert_select "button", text: "Check now", count: 0
  end

  # --- new / create ---

  test "new shows the form with the default interval and no locked options when self-hosted" do
    get new_project_uptime_monitor_path(@project)

    assert_response :success
    assert_select "form[action=?]", project_uptime_monitors_path(@project) do
      assert_select "input[type=url][name='uptime_monitor[url]'][autocomplete=off][required]"
      assert_select "input[name='uptime_monitor[name]']"
      assert_select "select[name='uptime_monitor[interval_minutes]'] option", 4
      assert_select "option[value='10'][selected]", "Every 10 minutes"
    end
  end

  test "hosted, new disables the locked intervals with Upgrade to unlock" do
    sign_in_as users(:outsider)

    with_hosted_mode { with_upgrade_url { get new_project_uptime_monitor_path(projects(:umbrella_app)) } }

    assert_select "option[value='1'][disabled][title='Upgrade to unlock']", "Every minute · Upgrade to unlock"
    assert_select "option[value='5']:not([disabled])", "Every 5 minutes"
    assert_select "option[value='10'][selected]"
    assert_select "p.hint", /Some intervals aren't available on this account\.\s*Upgrade to unlock/
  end

  test "hosted without an upgrade URL, new greys out the locked intervals as coming soon" do
    accounts(:acme).update!(entitlement_values: { "max_monitors" => 10 })
    with_hosted_mode { with_upgrade_url(nil) { get new_project_uptime_monitor_path(projects(:marketing)) } }

    assert_select "option[value='1'][disabled][title='Coming soon']", "Every minute · Coming soon"
    assert_select "option[value='5'][disabled][title='Coming soon']", "Every 5 minutes · Coming soon"
    assert_select "option[value='10']:not([disabled])", "Every 10 minutes"
    assert_select "p#uptime_monitor_interval_hint", "Some intervals are coming soon."
    assert_no_match "Upgrade", response.body
  end

  test "hosted at the limit, new shows the limit panel instead of the form" do
    with_hosted_mode { with_upgrade_url { get new_project_uptime_monitor_path(@project) } }

    assert_response :success
    assert_select "#uptime_monitor_limit h2", "This account has reached its limit of 1 monitor."
    assert_select "#uptime_monitor_limit a[href=?]", "https://billing.example/upgrade", text: "Upgrade to unlock"
    assert_select "form[action=?]", project_uptime_monitors_path(@project), count: 0
  end

  test "hosted at the limit without an upgrade URL, new says more are coming soon" do
    with_hosted_mode { with_upgrade_url(nil) { get new_project_uptime_monitor_path(@project) } }

    assert_response :success
    assert_select "#uptime_monitor_limit h2", "Cannot add more yet, but it's coming soon"
    assert_select "#uptime_monitor_limit p", count: 0
    assert_select "#uptime_monitor_limit a[href=?]", project_uptime_monitors_path(@project), text: "Back to Uptime"
    assert_select "form[action=?]", project_uptime_monitors_path(@project), count: 0
    assert_no_match "Upgrade", response.body
  end

  test "create adds a monitor, names it after the host and keeps the URL out of the logs" do
    log = capture_log do
      assert_difference -> { @project.uptime_monitors.count } do
        post project_uptime_monitors_path(@project),
          params: { uptime_monitor: { name: "", url: "https://shop.example/health?token=#{SECRET}", interval_minutes: "5" } }
      end
    end

    monitor = @project.uptime_monitors.order(:id).last
    assert_redirected_to project_uptime_monitor_path(@project, monitor)
    assert_equal "Added shop.example. Its first check runs within a minute.", flash[:notice]
    assert_equal [ "shop.example", 5, "pending" ], [ monitor.name, monitor.interval_minutes, monitor.status ]
    assert_no_match SECRET, log
  end

  test "create re-renders the form with whole-sentence errors" do
    assert_no_difference -> { UptimeMonitor.count } do
      post project_uptime_monitors_path(@project), params: { uptime_monitor: { name: "x" * 61, url: "http://10.0.0.1/" } }
    end

    assert_response :unprocessable_entity
    assert_select "#uptime_monitor_errors li", "URL must be a public http:// or https:// address."
    assert_select "#uptime_monitor_errors li", "Name is too long (maximum is 60 characters)."
    assert_select "input[name='uptime_monitor[url]'][aria-invalid=true]"
  end

  test "create ignores attributes outside the form" do
    post project_uptime_monitors_path(@project),
      params: { uptime_monitor: { url: "https://shop.example/", project_id: projects(:umbrella_app).id, status: "up",
                                  paused_at: Time.current } }

    monitor = UptimeMonitor.order(:id).last
    assert_equal [ @project, "pending", nil ], [ monitor.project, monitor.status, monitor.paused_at ]
  end

  test "hosted, a crafted create over the account's limit is rejected" do
    with_hosted_mode do
      assert_no_difference -> { UptimeMonitor.count } do
        with_upgrade_url { post project_uptime_monitors_path(projects(:marketing)), params: { uptime_monitor: { url: "https://shop.example/" } } }
      end
    end

    assert_response :unprocessable_entity
    assert_select "#uptime_monitor_limit h2", "This account has reached its limit of 1 monitor."
  end

  test "hosted without an upgrade URL, a crafted create over the limit says coming soon" do
    with_hosted_mode do
      assert_no_difference -> { UptimeMonitor.count } do
        with_upgrade_url(nil) { post project_uptime_monitors_path(projects(:marketing)), params: { uptime_monitor: { url: "https://shop.example/" } } }
      end
    end

    assert_response :unprocessable_entity
    assert_select "#uptime_monitor_limit h2", "Cannot add more yet, but it's coming soon"
  end

  test "hosted, a crafted create with a locked interval is rejected" do
    sign_in_as users(:outsider)

    with_hosted_mode do
      assert_no_difference -> { UptimeMonitor.count } do
        post project_uptime_monitors_path(projects(:umbrella_app)),
          params: { uptime_monitor: { url: "https://shop.example/", interval_minutes: "1" } }
      end
    end

    assert_response :unprocessable_entity
    assert_select "#uptime_monitor_errors li", "Check interval isn't available on this account."
  end

  test "new and create need a confirmed email" do
    users(:philip).update_columns(email_verified_at: nil)

    get new_project_uptime_monitor_path(@project)
    assert_redirected_to root_path
    assert_match "Confirm your email address first", flash[:alert]

    assert_no_difference -> { UptimeMonitor.count } do
      post project_uptime_monitors_path(@project), params: { uptime_monitor: { url: "https://shop.example/" } }
    end
    assert_redirected_to root_path
  end

  # --- edit / update / destroy ---

  test "edit fills the form with the full URL and is never cached" do
    get edit_project_uptime_monitor_path(@project, @monitor)

    assert_response :success
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_select "form[action=?]", project_uptime_monitor_path(@project, @monitor) do
      assert_select "input[name='uptime_monitor[url]'][value=?]", "https://storefront.example/up?token=uptime-fixture-secret"
      assert_select "option[value='10'][selected]"
    end
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "update saves the name, URL and interval" do
    patch project_uptime_monitor_path(@project, @monitor),
      params: { uptime_monitor: { name: "Home page", url: "https://storefront.example/", interval_minutes: "60" } }

    assert_redirected_to project_uptime_monitor_path(@project, @monitor)
    assert_equal "Saved Home page.", flash[:notice]
    assert_equal [ "Home page", "https://storefront.example/", 60 ], @monitor.reload.values_at(:name, :url, :interval_minutes)
  end

  test "update re-renders the form when invalid" do
    patch project_uptime_monitor_path(@project, @monitor), params: { uptime_monitor: { url: "ftp://storefront.example/" } }

    assert_response :unprocessable_entity
    assert_select "#uptime_monitor_errors li", "URL must be a public http:// or https:// address."
    assert_select "nav[aria-label=Breadcrumb]", /Storefront home/
    assert_equal "https://storefront.example/up?token=#{SECRET}", @monitor.reload.url
  end

  test "hosted, a crafted update to a locked interval is rejected" do
    with_hosted_mode do
      patch project_uptime_monitor_path(@project, @monitor), params: { uptime_monitor: { interval_minutes: "5" } }
    end

    assert_response :unprocessable_entity
    assert_select "#uptime_monitor_errors li", "Check interval isn't available on this account."
    assert_equal 10, @monitor.reload.interval_minutes
  end

  test "destroy deletes the monitor and its history" do
    assert_difference -> { UptimeMonitor.count } => -1, -> { UptimeCheck.count } => -6 do
      delete project_uptime_monitor_path(@project, @monitor)
    end

    assert_redirected_to project_uptime_monitors_path(@project)
    assert_response :see_other
    assert_equal "Deleted Storefront home.", flash[:notice]
  end

  test "a member who isn't an owner can manage monitors, like Settings › General" do
    sign_in_as users(:jo)

    post project_uptime_monitors_path(@project), params: { uptime_monitor: { url: "https://shop.example/" } }
    monitor = UptimeMonitor.order(:id).last
    assert_redirected_to project_uptime_monitor_path(@project, monitor)

    patch project_uptime_monitor_path(@project, monitor), params: { uptime_monitor: { name: "Shop" } }
    assert_equal "Shop", monitor.reload.name

    delete project_uptime_monitor_path(@project, monitor)
    assert_not UptimeMonitor.exists?(monitor.id)
  end

  # --- authorization ---

  test "signed-out requests go to sign in" do
    sign_out

    each_request(@project, @monitor) do |verb, path, params|
      public_send(verb, path, params:)
      assert_redirected_to new_session_path, "#{verb} #{path}"
    end
    assert @monitor.reload.persisted?
  end

  test "outsiders get 404 for every action and change nothing" do
    sign_in_as users(:outsider)

    assert_no_difference -> { UptimeMonitor.count } do
      each_request(@project, @monitor) do |verb, path, params|
        public_send(verb, path, params:)
        assert_response :not_found, "#{verb} #{path}"
      end
    end
    assert_equal "Storefront home", @monitor.reload.name
  end

  test "a monitor of another app is a 404 under this app's slug" do
    other = uptime_monitors(:billing_checkout)

    each_request(@project, other).reject { |_, path, _| path == project_uptime_monitors_path(@project) || path.end_with?("/new") }
      .each do |verb, path, params|
        public_send(verb, path, params:)
        assert_response :not_found, "#{verb} #{path}"
      end
    assert_equal "Billing checkout", other.reload.name
  end

  private
    def each_request(project, monitor)
      requests = [
        [ :get, project_uptime_monitors_path(project), {} ],
        [ :get, new_project_uptime_monitor_path(project), {} ],
        [ :post, project_uptime_monitors_path(project), { uptime_monitor: { url: "https://shop.example/" } } ],
        [ :get, project_uptime_monitor_path(project, monitor), {} ],
        [ :get, edit_project_uptime_monitor_path(project, monitor), {} ],
        [ :patch, project_uptime_monitor_path(project, monitor), { uptime_monitor: { name: "Hijacked" } } ],
        [ :delete, project_uptime_monitor_path(project, monitor), {} ]
      ]
      return requests unless block_given?

      requests.each { |request| yield(*request) }
    end

    def count_request_queries(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
end
