require "test_helper"

class StaffHelperTest < ActionView::TestCase
  test "entitlement values read like the config defaults" do
    assert_equal "10, 60 minutes", staff_entitlement_value("uptime_intervals", [ 10, 60 ])
    assert_equal "1 minute", staff_entitlement_value("uptime_intervals", [ 1 ])
    assert_equal "30, 60, 90 days", staff_entitlement_value("retention_days", [ 30, 60, 90 ])
    assert_equal "1 day", staff_entitlement_value("apm_retention_days", 1)
    assert_equal "3,000", staff_entitlement_value("monthly_event_quota", 3_000)
    assert_equal "No limit", staff_entitlement_value("max_projects", nil)
  end

  test "entitlement rows show the hosted value and where it comes from" do
    account = accounts(:umbrella)
    account.update_column(:entitlement_values, { "max_monitors" => 3, "monthly_event_quota" => nil })

    rows = staff_entitlement_rows(Staff::EntitlementsForm.new(account)).index_by(&:key)

    assert_equal [ "3", "Stored" ], [ rows["max_monitors"].value, rows["max_monitors"].source ]
    assert_equal [ "2", "Default" ], [ rows["max_projects"].value, rows["max_projects"].source ]
    assert_equal [ "3,000", "Default (the stored value is invalid)" ],
                 [ rows["monthly_event_quota"].value, rows["monthly_event_quota"].source ]
  end

  test "pagination renders nothing for a single page" do
    assert_nil staff_pagination(Pagy::Offset.new(count: 3, page: 1, limit: 25))
  end
end
