require "application_system_test_case"

class SetupPageSystemTest < ApplicationSystemTestCase
  setup do
    @project = projects(:marketing)
    sign_in
  end

  test "switching to Ruby in Settings › General shows the Ruby setup steps" do
    visit_connected edit_project_path(@project)
    type_into find_field("Platform"), "ruby"
    press find_button("Save changes")
    assert_text "Settings saved."

    visit_connected project_setup_path(@project)

    assert_selector "h2", text: "ii.Hook it in"
    assert_selector "#hook_rack", visible: true, text: "use GoodSorcery::Rack::Middleware"
    assert_selector "#hook_sidekiq", visible: false
    assert_no_selector "#install_generator", visible: :all

    press find("[role=tab]", text: "Sidekiq")

    assert_selector "#hook_sidekiq", visible: true, text: "GoodSorcery::Integrations::Sidekiq.install"
    assert_selector "#hook_rack", visible: false
  end

  test "copying the Ruby install snippet leaves out the prompts and keeps the full key" do
    @project.update!(platform: "ruby")
    visit_connected project_setup_path(@project)
    stub_clipboard

    within("#install_manual") { press first(:button, "Copy") }

    assert_equal "bundle add goodsorcery\nexport GOODSORCERY_API_KEY=#{FIXTURE_TOKENS[:marketing_production]}", copied_text
  end

  test "desktop code panes keep their plain look: no scroll shadow and the small Copy" do
    visit_connected project_setup_path(@project)
    styles = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".code-pane-body")].filter((pane) => pane.offsetParent).map((pane) => {
        const button = pane.parentElement.querySelector(".code-pane-header button")
        return [getComputedStyle(pane).backgroundImage, getComputedStyle(button).paddingLeft, button.getBoundingClientRect().height < 24]
      })
    JS
    assert styles.any?
    assert_equal [ [ "none", "0px", true ] ], styles.uniq
  end

  test "the MCP card appears in the rail when the first event lands" do
    visit_connected project_setup_path(@project)
    assert_selector "##{dom_id(@project, :setup_mcp)}[hidden]", visible: :hidden
    assert_no_link "Set up MCP"

    @project.record_first_event(runtime_label: "Rails 8.1 · Ruby 4.0", at: Time.current)
    stream "reload_frame", target: dom_id(@project, :listening), src: project_listening_path(@project)

    within("aside ##{dom_id(@project, :setup_mcp)}") do
      assert_text "Use it from your AI assistant"
      assert_link "Set up MCP →", href: access_tokens_path
    end
    assert_selector "##{dom_id(@project, :setup_mcp)}", count: 1
    assert_selector "##{dom_id(@project, :setup_hero)} .eyebrow", text: /connected/i
  end

  test "the MCP card fits a narrow screen" do
    page.current_window.resize_to(390, 844)
    visit_connected project_setup_path(projects(:storefront))
    width = page.evaluate_script("window.innerWidth")
    assert_operator width, :<, 640, "the window should be phone-sized"

    card = find("##{dom_id(projects(:storefront), :setup_mcp)}")
    assert_operator page.evaluate_script("arguments[0].getBoundingClientRect().right", card), :<=, width
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
  ensure
    page.current_window.resize_to(1440, 900)
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
