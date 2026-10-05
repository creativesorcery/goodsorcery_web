require "application_system_test_case"

class IssuePageSystemTest < ApplicationSystemTestCase
  setup do
    @project = projects(:storefront)
    sign_in
  end

  test "framework frames fold and unfold" do
    visit_connected project_issue_path(@project, issues(:nomethod))
    assert_selector "button.toggle[aria-pressed=false]", text: "Show framework frames"
    assert_text(/\d+ framework frames? hidden/)

    press find("button.toggle", text: "Show framework frames")

    assert_selector "button.toggle[aria-pressed=true]", text: "Show framework frames"
    assert_no_text(/\d+ framework frames? hidden/)
  end

  test "context tabs switch panels" do
    visit_connected project_issue_path(@project, issues(:nomethod))
    assert_selector "#context-request", visible: true
    assert_selector "#context-headers", visible: false

    press find("[role=tab]", text: "Headers")

    assert_selector "#context-headers", visible: true
    assert_selector "#context-request", visible: false
    assert_selector "[role=tab][aria-selected=true]", text: "Headers"
  end

  test "copying the install snippet leaves out the prompt and the masked key" do
    visit_connected project_setup_path(@project)
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard", { configurable: true,
        value: { writeText: (text) => { window.copiedText = text; return Promise.resolve() } } })
    JS

    within("#install_generator") { press find_button("Copy") }

    copied = Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until (text = page.evaluate_script("window.copiedText"))
      text
    end
    assert_equal "bundle add goodsorcery\nbin/rails generate goodsorcery:install YOUR_PRODUCTION_KEY", copied
  end

  test "dropdowns close on Escape and on outside clicks" do
    visit_connected project_issues_path(@project)
    button = find("[data-dropdown-target=button]", text: /Sort/)

    press button
    assert_selector "[data-dropdown-target=button][aria-expanded=true]", text: /Sort/
    press_key button, "Escape"
    assert_no_selector "[data-dropdown-target=button][aria-expanded=true]"

    press button
    assert_selector "[data-dropdown-target=button][aria-expanded=true]", text: /Sort/
    press find("h1")
    assert_no_selector "[data-dropdown-target=button][aria-expanded=true]"
  end
end
