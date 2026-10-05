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
end
