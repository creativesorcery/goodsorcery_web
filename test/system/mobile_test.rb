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

  test "pinch-zoom stays available" do
    viewport = page.evaluate_script(%(document.querySelector("meta[name=viewport]").content))
    assert_no_match(/maximum-scale|user-scalable/, viewport)
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.documentElement).touchAction")
    Dir[Rails.root.join("public/*.html")].each do |file|
      assert_no_match(/maximum-scale|user-scalable|touch-action/, File.read(file), File.basename(file))
    end
  end

  test "a row checkbox takes taps around it, not the issue link under them" do
    hits = page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector("[data-bulk-selection-target=checkbox]")
        box.scrollIntoView({ block: "center" })
        const rect = box.getBoundingClientRect()
        const x = rect.left + rect.width / 2, y = rect.top + rect.height / 2
        const points = [[x, rect.bottom + 14], [x, rect.top - 14], [rect.right + 12, y], [rect.left - 14, y]]
        return points.map(([px, py]) => document.elementFromPoint(px, py)?.closest("label")?.contains(box) || false)
      })()
    JS
    assert_equal [ true ] * 4, hits
  end

  test "in phone landscape the whole drawer scrolls, so the nav and the project switcher fit" do
    page.current_window.resize_to(740, 360)
    visit_connected project_issues_path(@project)
    press menu_button
    assert_drawer_open

    nav = page.evaluate_script("(() => { const nav = document.querySelector('#sidebar nav'); return [nav.clientHeight, nav.scrollHeight] })()")
    assert_operator nav.first, :>=, nav.last, "the nav is squeezed to #{nav.first}px of #{nav.last}px"

    press find("#sidebar [data-dropdown-target=button]", match: :first)
    last_entry_bottom = page.evaluate_script(<<~JS)
      (() => {
        const last = document.querySelector("#sidebar [data-dropdown-target=menu]").lastElementChild
        last.scrollIntoView({ block: "end" })
        return last.getBoundingClientRect().bottom - window.innerHeight
      })()
    JS
    assert_operator last_entry_bottom, :<=, 0, "the switcher's last entry stays #{last_entry_bottom}px below the screen"
  ensure
    page.current_window.resize_to(390, 844)
  end

  test "a long snippet file name truncates and leaves Copy inside the code pane" do
    visit_connected project_setup_path(projects(:marketing))
    press find("[role=tab]", text: "Manual")
    assert_selector "#install_manual", visible: true

    spill = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#install_manual .code-pane-header")].map((header) =>
        header.querySelector("button").getBoundingClientRect().right - header.getBoundingClientRect().right)
    JS
    assert spill.any?
    assert spill.all? { |px| px <= 0 }, "Copy spills out by #{spill.inspect}px"
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
