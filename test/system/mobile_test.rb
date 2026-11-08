require "application_system_test_case"

# Phone-sized checks: the sidebar drawer (drawer_controller) and pages that
# must fit the screen without scrolling sideways.
class MobileSystemTest < ApplicationSystemTestCase
  # Its own driver name, so Capybara keeps a separate (phone-sized) browser session.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ], options: { name: :selenium_phone }

  setup do
    @project = projects(:storefront)
    sign_in
    visit_connected project_issues_path(@project)
    assert_operator page.evaluate_script("window.innerWidth"), :<, 1024, "the window should be phone-sized"
  end

  test "the menu button opens the drawer, moves focus into it and locks the page; Escape closes it" do
    assert_drawer_closed
    press menu_button

    assert_drawer_open
    assert_equal "true", menu_button[:"aria-expanded"]
    assert_equal "sidebar", menu_button[:"aria-controls"]
    assert page.evaluate_script("document.getElementById('sidebar').contains(document.activeElement)")
    assert page.evaluate_script("document.body.classList.contains('drawer-open')")
    within("#sidebar") { assert_link "Performance" }

    press_key find("#sidebar"), "Escape"
    assert_drawer_closed
    assert_equal "false", menu_button[:"aria-expanded"]
    assert_not page.evaluate_script("document.body.classList.contains('drawer-open')")
    assert page.evaluate_script("document.activeElement.getAttribute('aria-label') === 'Open menu'")
  end

  test "the backdrop and the close button close the drawer" do
    press menu_button
    assert_drawer_open
    press find(".drawer-backdrop", visible: :all)
    assert_drawer_closed

    press menu_button
    assert_drawer_open
    press find("#sidebar button[aria-label='Close menu']")
    assert_drawer_closed
  end

  test "following a link in the drawer closes it" do
    press menu_button
    assert_drawer_open
    # Keep the page so the drawer's own reaction can be checked.
    page.execute_script("document.addEventListener('turbo:before-visit', (event) => event.preventDefault(), { once: true })")
    press find("#sidebar a", text: "Performance")
    assert_drawer_closed
  end

  test "Tab stays inside the open drawer" do
    press menu_button
    assert_drawer_open
    page.execute_script(<<~JS)
      const items = [...document.querySelectorAll("#sidebar a[href], #sidebar button:not([disabled])")].filter((element) => element.offsetParent)
      items[items.length - 1].focus()
    JS
    press_key find("#sidebar"), "Tab"
    assert page.evaluate_script("document.getElementById('sidebar').contains(document.activeElement)")
    assert page.evaluate_script("document.activeElement === document.querySelector('#sidebar a[href]')")
  end

  test "key pages fit the screen without sideways scrolling" do
    paths = [
      projects_path, project_issues_path(@project), project_issue_path(@project, issues(:nomethod)),
      project_performance_path(@project), project_uptime_monitors_path(@project), project_uptime_monitor_path(@project, uptime_monitors(:storefront_home)),
      project_setup_path(@project), edit_project_path(@project), project_alerts_path(@project), notifications_path, search_path(q: "error")
    ]
    paths.each do |path|
      visit_connected path
      overflow = page.evaluate_script("document.documentElement.scrollWidth - window.innerWidth")
      assert_operator overflow, :<=, 0, "#{path} scrolls sideways by #{overflow}px"
    end
  end

  test "fields are at least 16px so iOS doesn't zoom in on focus" do
    sizes = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("input:not([type=checkbox]):not([type=hidden]), select, textarea")]
        .map((field) => parseFloat(getComputedStyle(field).fontSize))
    JS
    assert sizes.any?
    assert sizes.all? { |size| size >= 16 }, "field font sizes: #{sizes.inspect}"
  end

  private
    def menu_button
      find("button[aria-label='Open menu']")
    end

    def assert_drawer_open
      assert_selector "#sidebar[data-open]"
      assert_selector ".drawer-backdrop", visible: true
    end

    def assert_drawer_closed
      assert_no_selector "#sidebar[data-open]", visible: :all
      assert_selector ".drawer-backdrop", visible: :hidden
    end
end
