require "test_helper"

class Staff::AccountsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:staffer) }

  test "index lists every account, newest first, with user counts, in the staff layout" do
    get staff_accounts_path

    assert_response :success
    assert_select "h1", /Accounts/
    assert_select "#sidebar a.nav-link[aria-current=page][href=?]", staff_accounts_path, text: "Accounts"
    assert_select "#sidebar a.nav-link[href=?]", staff_users_path, text: "Users"
    assert_select "#sidebar a[href=?]", root_path, text: "Back to the app"
    assert_select "#staff_accounts tbody tr", Account.count
    assert_equal Account.order(id: :desc).map { |account| dom_id(account, :staff) }, css_select("#staff_accounts tbody tr").pluck("id")
    assert_select "##{dom_id(accounts(:acme), :staff)}" do
      assert_select "a[href=?]", staff_account_path(accounts(:acme)), text: "Acme Labs"
      assert_select "td", text: "2"
    end
  end

  test "the staff root is the accounts list" do
    get staff_root_path
    assert_response :success
    assert_select "#staff_accounts"
  end

  test "index costs the same number of queries however many accounts are listed" do
    get staff_accounts_path
    few = count_queries { get staff_accounts_path }
    5.times { |n| Account.create!(name: "Extra #{n}").memberships.create!(user: users(:jo), role: :member) }

    assert_equal few, count_queries { get staff_accounts_path }
  end

  test "index searches by name, case-insensitively, or by exact id" do
    get staff_accounts_path(q: "UMBRELLA")
    assert_select "#staff_accounts tbody tr", 1
    assert_select "#staff_accounts", text: /Umbrella Corp/
    assert_select "input[name=q][value=UMBRELLA]"

    get staff_accounts_path(q: accounts(:acme).id)
    assert_select "#staff_accounts tbody tr", 1
    assert_select "#staff_accounts", text: /Acme Labs/
  end

  test "index matches LIKE wildcards literally" do
    Account.create!(name: "100% Real")

    get staff_accounts_path(q: "%")
    assert_select "#staff_accounts tbody tr", 1
    assert_select "#staff_accounts", text: /100% Real/

    get staff_accounts_path(q: "_")
    assert_select "#staff_accounts", 0
    assert_select "p", text: "No accounts match “_”."
  end

  test "index pages through accounts 25 at a time, keeping the search" do
    30.times { |n| Account.create!(name: "Paged #{n}") }

    get staff_accounts_path(q: "paged")
    assert_select "#staff_accounts tbody tr", 25
    assert_select "nav.pagy a[href*='page=2'][href*='q=paged']", text: "2"
    assert_select "#staff_accounts", text: /Paged 29/

    get staff_accounts_path(q: "paged", page: 2)
    assert_select "#staff_accounts tbody tr", 5
    assert_select "#staff_accounts", text: /Paged 0/
    assert_select "nav.pagy a[aria-current=page]", text: "2"
  end

  test "a page past the end says so and links back to page 1, keeping the search" do
    get staff_accounts_path(q: "acme", page: 5)

    assert_response :success
    assert_select "#staff_accounts", 0
    assert_select "p", text: /This page is past the end\./
    assert_select "a[href=?]", staff_accounts_path(q: "acme"), text: "Go to page 1"
  end

  test "each row's name link covers the whole row" do
    get staff_accounts_path
    assert_select "##{dom_id(accounts(:acme), :staff)}.relative a[class*='after:inset-0'][href=?]", staff_account_path(accounts(:acme))
  end

  test "show loads the account's memberships in one query" do
    get staff_account_path(accounts(:acme))
    queries = capture_queries { get staff_account_path(accounts(:acme)) }

    assert_equal 1, queries.count { |sql| sql.include?('FROM "memberships"') }, queries.join("\n")
  end

  test "show lists the account's users with their roles and its entitlements" do
    get staff_account_path(accounts(:acme))

    assert_response :success
    assert_select "h1", "Acme Labs"
    assert_select "#account_users tbody tr", 2
    assert_select "##{dom_id(users(:alex), :staff)}" do
      assert_select "a[href=?]", staff_user_path(users(:alex)), text: "Alex Rivera"
      assert_select "td", text: "alex@example.com"
      assert_select ".chip", text: "Owner"
    end
    assert_select "##{dom_id(users(:jo), :staff)} .chip", text: "Member"
    assert_select "#entitlement_monthly_event_quota", text: /3,000.*Default/m
    assert_select "#entitlement_uptime_intervals", text: /10, 60 minutes/
    assert_select "a[href=?]", edit_staff_account_path(accounts(:acme)), text: "Edit entitlements"
  end

  test "show marks stored values" do
    get staff_account_path(accounts(:umbrella))

    assert_select "#entitlement_max_monitors", text: /3.*Stored/m
    assert_select "#entitlement_uptime_intervals", text: /5, 10, 60 minutes.*Stored/m
  end

  test "show lists the entitlements in the edit form's order" do
    get staff_account_path(accounts(:acme))
    show_order = css_select("#account_entitlements [id^=entitlement_]").map { |row| row["id"].delete_prefix("entitlement_") }

    get edit_staff_account_path(accounts(:acme))
    form_order = css_select("[id^=field_]").map { |field| field["id"].delete_prefix("field_") }

    assert_equal Staff::EntitlementsForm::KEYS, show_order
    assert_equal form_order, show_order
  end

  test "self-hosted, show and edit say saved values only apply in hosted mode" do
    get staff_account_path(accounts(:acme))
    assert_select "#self_hosted_notice", text: /only apply in hosted mode/
    get edit_staff_account_path(accounts(:acme))
    assert_select "#self_hosted_notice"

    with_hosted_mode do
      get staff_account_path(accounts(:acme))
      assert_select "#self_hosted_notice", 0
      get edit_staff_account_path(accounts(:acme))
      assert_select "#self_hosted_notice", 0
    end
  end

  test "edit shows every key with its field types and a Use default option naming the default" do
    get edit_staff_account_path(accounts(:umbrella))

    assert_response :success
    assert_select "form[action=?]", staff_account_path(accounts(:umbrella))
    assert_select "input[type=checkbox][name='entitlements[uptime_intervals][]']", 4
    assert_select "input#uptime_intervals_5[checked]"
    assert_select "input#uptime_intervals_1:not([checked])"
    assert_select "input[type=checkbox][name='entitlements[retention_days][]']", 3
    assert_select "input[type=number]#entitlements_max_monitors[value='3'][min='0'][step='1']"
    assert_select "input[type=number]#entitlements_apm_retention_days[min='1'][max='30']"
    assert_select "input[type=number]#entitlements_monthly_event_quota[min='1']"
    assert_select "input[type=radio]#setting_max_monitors_unlimited[value=unlimited]"
    assert_select "input[type=radio]#setting_max_projects_unlimited"
    assert_select "input#setting_monthly_event_quota_unlimited", 0
    assert_select "input[type=radio][name^='entitlements[setting]']", 14
    assert_select "#field_uptime_intervals", text: /Default \(10, 60 minutes\)/
    assert_select "#field_max_monitors", text: /Default \(1\)/
    assert_select "#field_monthly_event_quota", text: /Default \(3,000\)/
    assert_select "#field_retention_days", text: /Default \(30 days\)/
    assert_select "input#setting_max_monitors_custom[value=custom][checked]"
    assert_select "input#setting_max_monitors_default:not([checked])"
    assert_select "input#setting_max_projects_default[value=default][checked]"
    assert_select "#field_max_projects[data-controller=entitlement-setting] fieldset[data-entitlement-setting-target=fields] input#entitlements_max_projects"
  end

  test "update stores typed values and removes keys left to their default" do
    patch staff_account_path(accounts(:umbrella)), params: { entitlements: entitlements_params(
      uptime_intervals: [ "", "1", "5" ], max_projects: "5"
    ).deep_merge(setting: { max_monitors: "default", max_projects: "unlimited" }) }

    assert_redirected_to staff_account_path(accounts(:umbrella))
    assert_equal "Saved Umbrella Corp's entitlements.", flash[:notice]
    assert_equal({ "uptime_intervals" => [ 1, 5 ], "apm_retention_days" => 7, "max_projects" => nil,
                   "monthly_event_quota" => 20_000, "retention_days" => [ 30, 60 ] }, accounts(:umbrella).reload.entitlement_values)
  end

  test "update in hosted mode fits monitors and rewrites the cached quota answer" do
    account = accounts(:acme)
    add_events_this_month(projects(:storefront), 10)
    with_memory_cache do
      with_hosted_mode do
        patch staff_account_path(account), params: { entitlements: entitlements_params(max_monitors: "0", monthly_event_quota: "1") }

        assert_redirected_to staff_account_path(account)
        assert UptimeMonitor.where(project: account.projects).all?(&:paused?)
        assert Rails.cache.read(Account.over_quota_key(account.id))
      end
    end
  end

  test "invalid input re-renders the form with whole-sentence messages and saves nothing" do
    patch staff_account_path(accounts(:umbrella)), params: { entitlements: entitlements_params(
      monthly_event_quota: "0", uptime_intervals: [ "" ], apm_retention_days: "abc"
    ) }

    assert_response :unprocessable_entity
    assert_select "#entitlements_errors li", 3
    assert_select "#entitlements_errors", text: /Monthly event quota must be a whole number greater than 0\./
    assert_select "#entitlements_errors", text: /Uptime intervals must be a non-empty list/
    assert_select "#entitlements_errors", text: /APM retention days must be a whole number from 1 to 30\./
    assert_select "input#entitlements_monthly_event_quota[value='0'][aria-invalid=true]", 1, "the submitted values stay in the form"
    assert_select "#field_monthly_event_quota #monthly_event_quota_error", text: Entitlements::PROBLEMS["monthly_event_quota"]
    assert_select "#field_uptime_intervals fieldset[aria-describedby='uptime_intervals_error uptime_intervals_hint']"
    assert_select "#field_max_monitors #max_monitors_error", 0
    assert_equal({ "uptime_intervals" => [ 5, 10, 60 ], "max_monitors" => 3 }, accounts(:umbrella).reload.entitlement_values)
  end

  test "a re-rendered form keeps Default and No limit rows showing values, not blanks" do
    params = entitlements_params(apm_retention_days: "0").except(:uptime_intervals, :max_projects)
    patch staff_account_path(accounts(:umbrella)), params: { entitlements: params.deep_merge(setting: { uptime_intervals: "default", max_projects: "unlimited" }) }

    assert_response :unprocessable_entity
    assert_select "input#setting_uptime_intervals_default[checked]"
    assert_select "input#uptime_intervals_5[checked]", 1, "the stored choices, since the disabled boxes weren't sent"
    assert_select "input#setting_max_projects_unlimited[checked]"
    assert_select "input#entitlements_max_projects[value='2']", 1, "the default number, ready for Custom"
  end

  test "an unknown account is a 404" do
    get staff_account_path(id: 0)
    assert_response :not_found
  end

  private
    def entitlements_params(overrides = {})
      { uptime_intervals: [ "", "10" ], retention_days: [ "", "30", "60" ], max_monitors: "4", max_projects: "3",
        monthly_event_quota: "20000", apm_retention_days: "7",
        setting: Staff::EntitlementsForm::KEYS.index_with("custom") }.merge(overrides)
    end

    def count_queries(&block)
      capture_queries(&block).size
    end

    # Every SQL statement, cached ones too: the test's query cache outlives a request.
    def capture_queries(&block)
      queries = []
      recorder = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record", &block)
      queries
    end
end
