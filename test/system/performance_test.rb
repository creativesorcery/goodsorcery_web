require "application_system_test_case"

class PerformanceSystemTest < ApplicationSystemTestCase
  include ApmFixtureClock

  include ActionView::RecordIdentifier

  setup { sign_in }

  test "from the overview to an endpoint and one of its traces" do
    project = projects(:storefront)
    visit_connected project_performance_path(project)
    assert_selector "h1", text: "Performance"
    assert_selector "[data-tile=p95]", text: "Last hour"

    press find_link("Background jobs")
    assert_selector "a.tab[aria-selected=true]", text: "Background jobs"
    assert_selector "[data-apm-table] a", text: "Orders::PlaceJob"

    press find_link("Web requests")
    assert_selector "a.tab[aria-selected=true]", text: "Web requests"
    press find_link("1h")
    assert_selector "h1", text: "last hour"

    press find_link("CheckoutsController#create")
    assert_selector "h1", text: "CheckoutsController#create"
    assert_selector "nav[aria-label='Time range'] a[aria-current=true]", text: "1h"
    assert_selector "h2", text: "Where time goes"

    frame = "##{dom_id(apm_transactions(:checkout_create), :traces)}"
    # The frame's advance visit lands after its render; click on only once it has.
    after_turbo_load { within(frame) { press find_link("Newest") } }
    within(frame) { assert_selector "nav[aria-label='Sort traces'] a[aria-current=true]", text: "Newest" }
    assert_current_path(/traces=newest/)

    within(frame) { press first("a[aria-label^='Trace of']") }
    assert_selector "h1", text: "POST /checkout"
    assert_selector "h2", text: "Errors in this request"
    assert_selector "section a", text: "GS-1042"
  end

  private
    def after_turbo_load
      page.execute_script("window.apmLoaded = false; document.addEventListener('turbo:load', () => { window.apmLoaded = true }, { once: true })")
      yield
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until page.evaluate_script("window.apmLoaded") }
    end
end
