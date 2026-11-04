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
    account.monthly_event_quota = 1
    assert_equal 1.0, account.event_quota_fraction

    account.monthly_event_quota = 10_000_000
    assert_in_delta account.events_this_month / 10_000_000.0, account.event_quota_fraction

    assert_nil accounts(:umbrella).event_quota_fraction
  end

  test "over_quota? compares this month's events with the quota" do
    account = accounts(:acme)
    assert_not account.over_quota?, "no quota"

    account.update!(monthly_event_quota: 1)
    assert account.over_quota?
    account.update!(monthly_event_quota: account.events_this_month + 1)
    assert_not account.over_quota?
    assert_not Account.over_quota?(account.id)
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
    end
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
end
