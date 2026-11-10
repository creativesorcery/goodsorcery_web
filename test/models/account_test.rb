require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "accessible only by members" do
    assert accounts(:acme).accessible_by?(users(:philip))
    assert accounts(:acme).accessible_by?(users(:jo))
    assert_not accounts(:acme).accessible_by?(users(:outsider))
    assert_not accounts(:acme).accessible_by?(nil)
  end

  test "events this month sums project rollups since the start of the UTC month" do
    month_start = Time.current.utc.beginning_of_month
    expected = ProjectHourlyCount.where(project: accounts(:acme).projects, hour: month_start..).sum(:count)

    assert_operator expected, :>, 0
    assert_equal expected, accounts(:acme).events_this_month
  end

  test "events this month excludes other accounts" do
    assert_equal ProjectHourlyCount.where(project: projects(:umbrella_app)).where(hour: Time.current.utc.beginning_of_month..).sum(:count),
      accounts(:umbrella).events_this_month
  end

  test "event quota fraction is capped at 1 and nil without a quota" do
    account = accounts(:acme)
    with_hosted_mode do
      account.entitlement_values = { "monthly_event_quota" => 1 }
      assert_equal 1.0, account.event_quota_fraction

      account.entitlement_values = { "monthly_event_quota" => 10_000_000 }
      assert_in_delta account.events_this_month / 10_000_000.0, account.event_quota_fraction

      account.entitlement_values = {}
      assert_in_delta [ account.events_this_month / 3_000.0, 1.0 ].min, account.event_quota_fraction, 1e-9, "the hosted default"
    end
    assert_nil account.event_quota_fraction, "self-hosted has no quota"
  end

  test "over_quota? compares this month's events with the resolved monthly_event_quota" do
    account = accounts(:acme)
    add_events_this_month(projects(:storefront), 3_000)

    with_hosted_mode do
      assert account.over_quota?, "the hosted default of 3,000"
      assert Account.over_quota?(account.id)

      account.update_entitlements!("monthly_event_quota" => account.events_this_month + 1)
      assert_not account.over_quota?
      assert_not Account.over_quota?(account.id)

      error = assert_raises(ActiveRecord::RecordInvalid) { account.update_entitlements!("monthly_event_quota" => nil) }
      assert_equal [ Entitlements::PROBLEMS["monthly_event_quota"] ], error.record.errors[:base], "a quota is always stored as a number"
    end
  end

  test "self-hosted is never over quota, whatever is stored, and reads nothing" do
    account = accounts(:acme)
    account.update_entitlements!("monthly_event_quota" => 1)

    assert_not account.over_quota?
    assert_no_queries { assert_not Account.over_quota?(account.id) }
  end

  test "Account.over_quota? caches the answer per id and rewrites it when entitlement_values change" do
    account = accounts(:acme)
    add_events_this_month(projects(:storefront), 3_000)
    with_memory_cache do
      with_hosted_mode do
        assert Account.over_quota?(account.id)
        assert_no_queries { assert Account.over_quota?(account.id) }

        account.update_entitlements!("monthly_event_quota" => 10_000_000)
        assert_no_queries { assert_not Account.over_quota?(account.id), "rewritten on commit" }

        account.update_entitlements!({})
        assert_no_queries { assert Account.over_quota?(account.id), "back on the 3,000 default" }
        account.update_entitlements!("monthly_event_quota" => 10_000_000)

        account.update!(name: "Acme Renamed")
        assert_equal false, Rails.cache.read(Account.over_quota_key(account.id)), "other changes keep it"
      end
    end
  end

  test "a cache miss that read the account before a quota change can't overwrite the fresh answer" do
    account = accounts(:acme)
    add_events_this_month(projects(:storefront), 3_000)
    with_memory_cache do
      with_hosted_mode do
        stale = Account.find(account.id).over_quota? # an ingest miss, mid-flight
        account.update_entitlements!("monthly_event_quota" => 10_000_000)

        assert Account.remember_over_quota(account.id, stale, unless_exist: true), "the miss answers its own request"
        assert_no_queries { assert_not Account.over_quota?(account.id), "the next request sees the new quota" }
      end
    end
  end

  test "Account.over_quota? fills an empty cache on a miss" do
    account = accounts(:acme)
    add_events_this_month(projects(:storefront), 3_000)
    with_memory_cache do
      with_hosted_mode do
        Rails.cache.delete(Account.over_quota_key(account.id))
        assert Account.over_quota?(account.id)
        assert_equal true, Rails.cache.read(Account.over_quota_key(account.id))
      end
    end
  end

  test "Account.over_quota? keeps the answer for a minute only" do
    account = accounts(:acme)
    add_events_this_month(projects(:storefront), 3_000)
    with_memory_cache do
      with_hosted_mode do
        assert Account.over_quota?(account.id)
        account.update_column(:entitlement_values, { "monthly_event_quota" => 10_000_000 })
        assert Account.over_quota?(account.id), "a write that skips callbacks waits for the cache"

        travel Account::OVER_QUOTA_TTL + 1.second
        assert_not Account.over_quota?(account.id)
      end
    end
  end

  test "update_entitlements! stores retention_days and rejects invalid lists" do
    account = accounts(:acme)
    account.update_entitlements!("retention_days" => [ 30, 90 ])
    assert_equal({ "retention_days" => [ 30, 90 ] }, account.reload.entitlement_values)
    with_hosted_mode { assert_equal [ 30, 90 ], account.entitlements.retention_days }

    [ [], [ 45 ], [ 30, 30 ], "30", nil ].each do |value|
      error = assert_raises(ActiveRecord::RecordInvalid, value.inspect) { account.update_entitlements!("retention_days" => value) }
      assert_equal [ Entitlements::PROBLEMS["retention_days"] ], error.record.errors[:base]
    end
  end

  test "update_entitlements! drops unknown keys and reports every invalid one" do
    account = accounts(:acme)
    account.update_entitlements!("retention_days" => [ 30 ], "monthly_event_quota" => 9_000, "seats" => 4, "plan" => "x")
    assert_equal({ "retention_days" => [ 30 ], "monthly_event_quota" => 9_000 }, account.reload.entitlement_values)

    error = assert_raises(ActiveRecord::RecordInvalid) { account.update_entitlements!("retention_days" => [ 7 ], "monthly_event_quota" => 0) }
    assert_equal [ Entitlements::PROBLEMS["monthly_event_quota"], Entitlements::PROBLEMS["retention_days"] ].sort, error.record.errors[:base].sort
    assert_equal({ "retention_days" => [ 30 ], "monthly_event_quota" => 9_000 }, account.reload.entitlement_values, "nothing stored")
  end

  test "update_entitlements! stores monthly_event_quota and rejects invalid values" do
    account = accounts(:acme)
    account.update_entitlements!("monthly_event_quota" => 50_000)
    assert_equal({ "monthly_event_quota" => 50_000 }, account.reload.entitlement_values)

    [ nil, 0, -5, "100", 1.5, true, [ 10 ] ].each do |value|
      error = assert_raises(ActiveRecord::RecordInvalid, value.inspect) { account.update_entitlements!("monthly_event_quota" => value) }
      assert_equal [ Entitlements::PROBLEMS["monthly_event_quota"] ], error.record.errors[:base]
    end
  end

  test "new accounts store no entitlement values" do
    assert_equal({}, Account.create!(name: "Fresh").reload.entitlement_values)
  end

  test "entitlements are unlimited when self-hosted, whatever is stored" do
    entitlements = accounts(:umbrella).entitlements

    assert entitlements.unlimited?
    assert_equal Entitlements::UPTIME_INTERVALS, entitlements.uptime_intervals
    assert_nil entitlements.max_monitors
  end

  test "hosted entitlements use stored values, else the hosted defaults" do
    with_hosted_mode do
      assert_equal [ 5, 10, 60 ], accounts(:umbrella).entitlements.uptime_intervals
      assert_equal 3, accounts(:umbrella).entitlements.max_monitors
      assert_equal [ 10, 60 ], accounts(:acme).entitlements.uptime_intervals
      assert_equal 1, accounts(:acme).entitlements.max_monitors
      assert_equal 2, accounts(:acme).entitlements.max_projects
      assert_equal 3_000, accounts(:acme).entitlements.monthly_event_quota
    end
  end

  test "update_entitlements! stores max_projects, validated like max_monitors" do
    account = accounts(:acme)
    account.update_entitlements!("max_projects" => 10)

    assert_equal({ "max_projects" => 10 }, account.reload.entitlement_values)
    with_hosted_mode { assert_equal 10, account.entitlements.max_projects }
    with_hosted_mode(false) { assert_nil account.entitlements.max_projects }

    error = assert_raises(ActiveRecord::RecordInvalid) { account.update_entitlements!("max_projects" => -1) }
    assert_includes error.record.errors[:base], Entitlements::PROBLEMS["max_projects"]
  end

  test "entitlements reflect a fresh update" do
    account = accounts(:acme)
    account.update_entitlements!("max_monitors" => 7)

    with_hosted_mode { assert_equal 7, account.entitlements.max_monitors }
  end

  test "update_entitlements! replaces the whole document" do
    account = accounts(:umbrella)
    account.update_entitlements!("max_monitors" => nil)

    assert_equal({ "max_monitors" => nil }, account.reload.entitlement_values)
    with_hosted_mode do
      assert_nil account.entitlements.max_monitors, "null means no cap"
      assert_equal [ 10, 60 ], account.entitlements.uptime_intervals, "the dropped key falls back"
    end
  end

  test "update_entitlements! stores only known keys and logs unknown key names only" do
    account = accounts(:acme)

    log = capture_log { account.update_entitlements!(uptime_intervals: [ 1, 5 ], plan_secret: "do-not-log") }

    assert_equal({ "uptime_intervals" => [ 1, 5 ] }, account.reload.entitlement_values)
    assert_includes log, %(Dropping unknown entitlement keys "plan_secret" for account #{account.id})
    assert_not_includes log, "do-not-log"
  end

  test "update_entitlements! rejects invalid values and keeps the stored document" do
    account = accounts(:umbrella)
    before = account.entitlement_values

    error = assert_raises(ActiveRecord::RecordInvalid) do
      account.update_entitlements!("uptime_intervals" => [ 2 ], "max_monitors" => -1)
    end

    assert_includes error.record.errors[:base], Entitlements::PROBLEMS["uptime_intervals"]
    assert_includes error.record.errors[:base], Entitlements::PROBLEMS["max_monitors"]
    assert_equal before, account.reload.entitlement_values
  end

  test "update_entitlements! refuses unpermitted params" do
    params = ActionController::Parameters.new(max_monitors: 5)

    assert_raises(ActionController::UnfilteredParameters) { accounts(:acme).update_entitlements!(params) }
  end

  test "entitlement values must be an object" do
    account = accounts(:acme)
    account.entitlement_values = [ 1, 2 ]

    assert_not account.valid?
    assert_includes account.errors[:base], "Entitlements must be an object of values."
  end

  test "a hand-edited invalid document doesn't block unrelated saves and is ignored when read" do
    account = accounts(:acme)
    account.update_columns(entitlement_values: { "max_monitors" => "lots" })

    account.reload.update!(name: "Acme Renamed")
    with_hosted_mode { assert_equal 1, account.entitlements.max_monitors }
  end

  private
    def capture_log
      output = StringIO.new
      previous = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(output)
      yield
      output.string
    ensure
      Rails.logger = previous
    end

  test "staff_search matches a name substring, case-insensitively, or an exact id, with wildcards matched literally" do
    assert_equal [ accounts(:acme) ], Account.staff_search("acme").to_a
    assert_equal [ accounts(:umbrella) ], Account.staff_search("UMBRELLA corp").to_a
    assert_equal [ accounts(:umbrella) ], Account.staff_search(accounts(:umbrella).id.to_s).to_a
    assert_empty Account.staff_search("%")

    sale = Account.create!(name: "50% off")
    assert_equal [ sale ], Account.staff_search("%").to_a
  end

  test "with_users_count counts each account's members in the same query" do
    accounts = assert_queries_count(1) { Account.with_users_count.order(:id).to_a }

    assert_equal({ accounts(:acme) => 2, accounts(:umbrella) => 1, accounts(:staff_hq) => 1 },
                 accounts.to_h { |account| [ account, account.users_count ] })
  end
end
