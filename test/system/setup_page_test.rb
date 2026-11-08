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

  test "copying the Ruby install snippet leaves out the prompts and the masked key" do
    @project.update!(platform: "ruby")
    visit_connected project_setup_path(@project)
    stub_clipboard

    within("#install_manual") { press first(:button, "Copy") }

    assert_equal "bundle add goodsorcery\nexport GOODSORCERY_API_KEY=YOUR_PRODUCTION_KEY", copied_text
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
