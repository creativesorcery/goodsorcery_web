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

  test "the Job tab shows its panel and empty state" do
    visit_connected project_issue_path(@project, issues(:nomethod))
    assert_selector "#context-job", visible: false

    press find("[role=tab]", text: "Job")

    assert_selector "#context-job", visible: true, text: "No job was captured with this occurrence."
    assert_selector "#context-request", visible: false
    assert_selector "[role=tab][aria-selected=true]", text: "Job"
  end

  test "Ask your AI copies a prompt with the short id and app only, and says so" do
    issue = issues(:nomethod)
    PersonalAccessToken.revoke_all(user_id: users(:philip).id)
    visit_connected project_issue_path(@project, issue)
    stub_clipboard

    assert_link "Set up MCP", href: access_tokens_path
    button = find("#ask_your_ai button", text: "Ask your AI")
    press button

    assert_equal "Use the Good Sorcery MCP server to look into issue #{issue.short_id} in the storefront app " \
                 "and suggest a fix. Start with get_issue for #{issue.short_id}.", copied_text
    assert_selector "#ask_your_ai button", text: "Prompt copied ✓"
    assert_selector "#ask_your_ai button", text: "Ask your AI"
    assert_selector "#ask_your_ai button span[aria-hidden]", text: "✦"
  end

  test "copying the install snippet leaves out the prompt and the masked key" do
    visit_connected project_setup_path(@project)
    stub_clipboard

    within("#install_generator") { press find_button("Copy") }

    assert_equal "bundle add goodsorcery\nbin/rails generate goodsorcery:install --api-key=YOUR_PRODUCTION_KEY", copied_text
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

  private
    def stub_clipboard
      page.execute_script(<<~JS)
        Object.defineProperty(navigator, "clipboard", { configurable: true,
          value: { writeText: (text) => { window.copiedText = text; return Promise.resolve() } } })
      JS
    end

    def copied_text
      Timeout.timeout(Capybara.default_max_wait_time) do
        sleep 0.05 until (text = page.evaluate_script("window.copiedText"))
        text
      end
    end
end
