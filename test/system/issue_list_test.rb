require "application_system_test_case"

class IssueListSystemTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  setup do
    @project = projects(:storefront)
    sign_in
    visit_connected project_issues_path(@project)
  end

  test "ticking rows shows the bulk bar with the count, and Resolve resolves them" do
    assert_no_selector "[data-bulk-selection-target=bar]"
    press row_checkbox(issues(:nomethod))
    press row_checkbox(issues(:card_error))

    within "[data-bulk-selection-target=bar]" do
      assert_selector "[data-bulk-selection-target=count]", text: "2"
      press find_button("✓ Resolve")
    end

    assert_no_selector "##{dom_id(issues(:nomethod), :row)}"
    assert issues(:nomethod).reload.resolved?
    assert issues(:card_error).reload.resolved?
  end

  test "select all is indeterminate with some rows ticked, and Clear hides the bar" do
    press row_checkbox(issues(:nomethod))
    assert_selector "[data-bulk-selection-target=count]", text: "1"
    assert page.evaluate_script("document.querySelector('[data-bulk-selection-target=all]').indeterminate")

    press find_button("Clear")
    assert_no_selector "[data-bulk-selection-target=bar]"
    assert_not row_checkbox(issues(:nomethod)).checked?
  end

  test "a live rows reload refreshes every visible row in one request and keeps ticked rows ticked" do
    press row_checkbox(issues(:nomethod))
    Issue.where(id: issues(:nomethod).id).update_all(events_count: 98_765)

    stream "reload_rows", target: dom_id(@project, :issues), src: project_rows_path(@project)

    within("##{dom_id(issues(:nomethod), :row)}") { assert_text "98,765" }
    assert row_checkbox(issues(:nomethod)).checked?
    assert_selector "[data-bulk-selection-target=count]", text: "1"
  end

  test "the summary keeps the viewer's period through a live reload and does not fade out" do
    press find(".segmented a", text: "7d")
    assert_selector ".segmented a[aria-current=true]", text: "7d"

    stream "reload_frame", target: dom_id(@project, :summary), src: project_summary_path(@project)

    assert_selector ".segmented a[aria-current=true]", text: "7d"
    assert_no_selector "turbo-frame##{dom_id(@project, :summary)} .rise"
    assert_equal "1", page.evaluate_script("getComputedStyle(document.querySelector('section[aria-label=Summary]')).opacity")
  end

  private
    def row_checkbox(issue)
      find("input[type=checkbox][value='#{issue.id}']")
    end

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
