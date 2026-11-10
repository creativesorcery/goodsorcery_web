require "test_helper"

class Staff::EntitlementsFormTest < ActiveSupport::TestCase
  setup { @account = accounts(:umbrella) } # stores uptime_intervals [5, 10, 60] and max_monitors 3

  test "without params it shows what the account stores, and the hosted default for keys it doesn't" do
    form = Staff::EntitlementsForm.new(@account)

    assert_not form.use_default?("uptime_intervals")
    assert form.chosen?("uptime_intervals", 5)
    assert_not form.chosen?("uptime_intervals", 1)
    assert_equal 3, form.field_value("max_monitors")
    assert_not form.no_limit?("max_monitors")

    assert form.use_default?("monthly_event_quota")
    assert_equal 3_000, form.field_value("monthly_event_quota")
    assert form.use_default?("retention_days")
    assert form.chosen?("retention_days", 30)
  end

  test "a stored null cap shows as No limit" do
    @account.update!(entitlement_values: { "max_projects" => nil })

    form = Staff::EntitlementsForm.new(@account)
    assert_not form.use_default?("max_projects")
    assert form.no_limit?("max_projects")
  end

  test "translates the form into JSON integers, lists of integers and null" do
    form = Staff::EntitlementsForm.new(@account, params(
      "uptime_intervals" => [ "", "1", "60" ], "retention_days" => [ "", "30", "90" ],
      "max_monitors" => " 7 ", "max_projects" => "",
      "monthly_event_quota" => "250000", "apm_retention_days" => "14"
    ).merge(settings("max_projects" => "unlimited")))

    assert_equal({ "uptime_intervals" => [ 1, 60 ], "max_monitors" => 7, "apm_retention_days" => 14, "max_projects" => nil,
                   "monthly_event_quota" => 250_000, "retention_days" => [ 30, 90 ] }, form.entitlement_values)
    assert form.save
    assert_equal form.entitlement_values, @account.reload.entitlement_values
  end

  test "a key set to Default is removed from the stored document" do
    form = Staff::EntitlementsForm.new(@account, params(defaults("uptime_intervals", "max_monitors")))

    assert form.save
    assert_not @account.reload.entitlement_values.key?("uptime_intervals")
    assert_not @account.entitlement_values.key?("max_monitors")
    with_hosted_mode { assert_equal [ 10, 60 ], @account.entitlements.uptime_intervals }
  end

  test "Default ignores a value given for the same key" do
    form = Staff::EntitlementsForm.new(@account, params(defaults("max_monitors").merge("max_monitors" => "9")))

    assert_not form.entitlement_values.key?("max_monitors")
  end

  test "a key submitted without a setting, or with an unknown one, is left to its default" do
    form = Staff::EntitlementsForm.new(@account, params("setting" => { "max_monitors" => "custom", "max_projects" => "bogus" }))

    assert_equal({ "max_monitors" => 1 }, form.entitlement_values)
    assert Staff::EntitlementsForm.new(@account, params("setting" => "custom")).entitlement_values.empty?
  end

  test "No limit stores null for a cap and ignores its number; the monthly quota has no No limit" do
    form = Staff::EntitlementsForm.new(@account, params(settings("max_monitors" => "unlimited", "monthly_event_quota" => "unlimited")))

    assert form.no_limit?("max_monitors")
    assert_nil form.entitlement_values.fetch("max_monitors")
    assert_not form.no_limit?("monthly_event_quota")
    assert_not form.entitlement_values.key?("monthly_event_quota"), "an unknown setting is Default"
    assert_empty form.problems
  end

  test "a blank Custom cap is rejected" do
    form = Staff::EntitlementsForm.new(@account, params("max_projects" => "  "))

    assert_not form.save
    assert_equal Entitlements::PROBLEMS["max_projects"], form.problem("max_projects")
  end

  test "fields that weren't sent show what is stored, or the default" do
    @account.update!(entitlement_values: { "max_projects" => nil, "max_monitors" => 3 })
    form = Staff::EntitlementsForm.new(@account, { "setting" => { "max_projects" => "unlimited" } })

    assert_equal 3, form.field_value("max_monitors")
    assert_equal 2, form.field_value("max_projects"), "a stored No limit offers the default number"
    assert form.chosen?("uptime_intervals", 10)
    assert_equal "unlimited", Staff::EntitlementsForm.new(@account).setting("max_projects")
  end

  test "problems are keyed by field, and a key left to its default has none" do
    form = Staff::EntitlementsForm.new(@account, params({ "apm_retention_days" => "31", "monthly_event_quota" => "x" }.merge(defaults("monthly_event_quota"))))

    assert_equal({ "apm_retention_days" => Entitlements::PROBLEMS["apm_retention_days"] }, form.problems)
  end

  test "the hosted value of each key and where it comes from" do
    @account.update_column(:entitlement_values, { "max_monitors" => 3, "monthly_event_quota" => nil })
    form = Staff::EntitlementsForm.new(@account)

    assert_equal [ 3, :stored ], [ form.hosted_value("max_monitors"), form.source("max_monitors") ]
    assert_equal [ 2, :default ], [ form.hosted_value("max_projects"), form.source("max_projects") ]
    assert_equal [ 3_000, :invalid ], [ form.hosted_value("monthly_event_quota"), form.source("monthly_event_quota") ]
  end

  test "text that isn't a whole number is rejected with Entitlements' sentences, and nothing is saved" do
    before = @account.entitlement_values
    form = Staff::EntitlementsForm.new(@account, params(
      "monthly_event_quota" => "", "max_monitors" => "2.5", "apm_retention_days" => "31", "retention_days" => [ "" ]
    ))

    assert_not form.save
    assert_equal [ Entitlements::PROBLEMS["max_monitors"], Entitlements::PROBLEMS["apm_retention_days"],
                   Entitlements::PROBLEMS["monthly_event_quota"], Entitlements::PROBLEMS["retention_days"] ].sort,
                 form.errors[:base].sort
    assert_equal before, @account.reload.entitlement_values
    assert_not @account.changed?, "the rejected values aren't left on the account"
  end

  test "problems follow the form's order" do
    form = Staff::EntitlementsForm.new(@account, params("apm_retention_days" => "0", "max_projects" => "-1", "uptime_intervals" => [ "" ]))

    assert_equal %w[ uptime_intervals max_projects apm_retention_days ], form.problems.keys
    assert_equal Entitlements::KEYS.sort, Staff::EntitlementsForm::KEYS.sort, "the form covers every key"
  end

  test "a monthly quota of 0 is rejected" do
    form = Staff::EntitlementsForm.new(@account, params("monthly_event_quota" => "0"))

    assert_not form.save
    assert_equal [ Entitlements::PROBLEMS["monthly_event_quota"] ], form.errors[:base]
  end

  test "saving runs the account's commit callbacks: fitting and the cached quota answer" do
    account = accounts(:acme)
    add_events_this_month(projects(:storefront), 10)
    with_memory_cache do
      with_hosted_mode do
        Staff::EntitlementsForm.new(account, params("max_monitors" => "0", "monthly_event_quota" => "1")).save

        assert account.projects.flat_map(&:uptime_monitors).all?(&:paused?), "monitors fitted to a cap of 0"
        assert_equal true, Rails.cache.read(Account.over_quota_key(account.id))
      end
    end
  end

  private
    # A valid, complete submission; overrides replace single fields.
    def params(overrides = {})
      { "uptime_intervals" => [ "", "10", "60" ], "retention_days" => [ "", "30" ], "max_monitors" => "1", "max_projects" => "2",
        "monthly_event_quota" => "5000", "apm_retention_days" => "1" }.merge(settings).merge(overrides)
    end

    # The setting param: every key Custom except the given changes.
    def settings(changes = {})
      { "setting" => Staff::EntitlementsForm::KEYS.index_with("custom").merge(changes) }
    end

    def defaults(*keys)
      settings(keys.index_with("default"))
    end
end
