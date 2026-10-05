require "test_helper"

# Browser tests for behaviour that only exists in JavaScript: the Stimulus
# controllers and the custom live-update stream actions (headless Chrome).
#
# Interactions go through the DOM (`press`, `press_key`, `type_into`:
# element.click(), dispatched keyboard events, value + input event) rather
# than WebDriver input, which headless Chrome intermittently stops delivering
# on some hosts. The page's own JavaScript handles them as it handles a user's.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 900 ]

  # Signs in through the real form, so the session cookie is the browser's.
  def sign_in(user = users(:philip), password: "password")
    visit new_session_path
    type_into find_field("email_address"), user.email_address
    type_into find_field("password"), password
    press find_button("Sign in")
    assert_no_current_path new_session_path
  end

  # Visits a page and waits until Stimulus has connected every controller on it.
  def visit_connected(path)
    visit path
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until stimulus_connected? }
  end

  def press(element)
    page.execute_script("arguments[0].click()", element)
  end

  def press_key(element, key)
    page.execute_script("arguments[0].dispatchEvent(new KeyboardEvent('keydown', { key: arguments[1], bubbles: true }))",
                        element, key)
  end

  def type_into(field, text)
    page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('input', { bubbles: true }))",
                        field, text)
  end

  private
    def stimulus_connected?
      page.evaluate_script(<<~JS)
        !!window.Stimulus && [...document.querySelectorAll("[data-controller]")].every((element) =>
          element.dataset.controller.split(/\\s+/).every((name) => window.Stimulus.getControllerForElementAndIdentifier(element, name)))
      JS
    end
end
