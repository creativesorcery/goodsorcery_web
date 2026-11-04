require "application_system_test_case"

class UptimeSystemTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  setup { sign_in }

  test "adding a monitor from the empty state, checking it now and deleting it" do
    project = projects(:marketing)
    visit_connected project_uptime_monitors_path(project)
    assert_selector "h2", text: "Watch your app from the outside"

    press find_link("Add a monitor")
    assert_selector "h1", text: "Add a monitor"
    type_into find_field("URL"), "https://marketing.example/up"
    type_into find_field("Name"), "Marketing home"
    type_into find_field("Check"), "60"
    press find_button("Add monitor")

    assert_text "Added Marketing home."
    assert_selector "h1", text: "Marketing home"
    assert_selector "p.font-mono", text: "https://marketing.example/up"
    assert_selector ".chip", text: "Every hour"
    monitor = project.uptime_monitors.find_by!(name: "Marketing home")
    assert_equal 60, monitor.interval_minutes

    press find_button("Check now")
    assert_text "Checking Marketing home now…"

    page.execute_script("window.confirm = () => true")
    press find_button("Delete")
    assert_text "Deleted Marketing home."
    assert_selector "h2", text: "Watch your app from the outside"
    assert_not UptimeMonitor.exists?(monitor.id)
  end

  test "a live reload after a check refreshes the monitor's row" do
    project = projects(:storefront)
    monitor = uptime_monitors(:storefront_home)
    visit_connected project_uptime_monitors_path(project)
    within("##{dom_id(monitor, :row)}") { assert_selector ".chip", text: "Up" }

    monitor.update_columns(status: "down", down_since: 3.minutes.ago)
    stream "reload_frame", target: dom_id(monitor, :row), src: project_uptime_monitor_row_path(project, monitor)

    within("##{dom_id(monitor, :row)}") { assert_selector ".chip", text: "Down for 3 min" }
    press find_link("Storefront home")
    assert_selector "h1", text: "Storefront home"
  end

  private
    # What Action Cable delivers: a pointer-only turbo-stream element.
    def stream(action, target:, src:)
      page.execute_script(<<~JS, action, target, src)
        const [action, target, src] = arguments
        const element = document.createElement("turbo-stream")
        element.setAttribute("action", action)
        element.setAttribute("target", target)
        element.setAttribute("src", src)
        element.appendChild(document.createElement("template"))
        document.body.appendChild(element)
      JS
    end
end
