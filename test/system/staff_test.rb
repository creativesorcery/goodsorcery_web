require "application_system_test_case"

class StaffSystemTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  test "staff open the staff area from the user menu, find an account and change its entitlements" do
    sign_in users(:staffer)
    visit_connected projects_path
    user_menu = find("aside [data-controller=dropdown]", text: users(:staffer).name)
    press user_menu.find("button")
    press user_menu.find_link("Staff")

    assert_selector "h1", text: "Accounts"
    type_into find_field("q"), "acme"
    page.execute_script("document.querySelector('form[role=search]').requestSubmit()")
    assert_selector "#staff_accounts tbody tr", count: 1
    press find_link("Acme Labs")

    assert_selector "h1", text: "Acme Labs"
    assert_selector "#self_hosted_notice"
    press find_link("Edit entitlements")
    assert_selector "#field_max_projects fieldset[data-entitlement-setting-target=fields][disabled]"
    press find_field("setting_max_projects_custom", visible: :all)
    assert_selector "#field_max_projects fieldset[data-entitlement-setting-target=fields]:not([disabled])"
    press find_field("setting_max_projects_default", visible: :all)
    assert_selector "#field_max_projects fieldset[data-entitlement-setting-target=fields][disabled]"
    press find_field("setting_max_monitors_custom", visible: :all)
    type_into find_field("entitlements_max_monitors"), "5"
    press find_button("Save entitlements")

    assert_text "Saved Acme Labs's entitlements."
    assert_selector "#entitlement_max_monitors", text: /5\s*Stored/
    assert_equal 5, accounts(:acme).reload.entitlement_values["max_monitors"]

    press find_link("Philip Nguyen")
    assert_selector "h1", text: "Philip Nguyen"
    press find_link("Back to the app")
    assert_current_path root_path
  end
end
