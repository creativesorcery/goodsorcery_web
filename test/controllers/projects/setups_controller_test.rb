require "test_helper"

class Projects::SetupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:philip)
  end

  test "a listening project shows step two of three" do
    get project_setup_path(projects(:marketing))

    assert_response :success
    assert_select "##{dom_id(projects(:marketing), :setup_hero)}" do
      assert_select ".eyebrow", "Step 2 of 3"
      assert_select "h1", text: /Add\s+marketing-site\s+to Good Sorcery/
      assert_select "ol li[aria-current=step]", text: /Install the gem/
    end
    assert_select "turbo-frame##{dom_id(projects(:marketing), :listening)}", text: /Listening for your first event/
  end

  test "a connected project says so and links to issues" do
    get project_setup_path(projects(:storefront))

    assert_select "##{dom_id(projects(:storefront), :setup_hero)}" do
      assert_select ".eyebrow", "Connected"
      assert_select "h1", text: /storefront\s+is connected/
      assert_select "a[href=?]", project_issues_path(projects(:storefront))
      assert_select "li[aria-current=step]", count: 0
    end
    assert_select "turbo-frame##{dom_id(projects(:storefront), :listening)}", text: /First event received/
  end

  test "install tabs show only the masked default key" do
    get project_setup_path(projects(:storefront))

    api_key = api_keys(:storefront_production)
    assert_select "[role=tab]", count: 3
    assert_select "[role=tab][aria-selected=true]", "Generator"
    assert_select "#install_generator pre", text: /bundle add goodsorcery/
    assert_select "#install_generator pre [data-clipboard-skip]", text: "gs_live_Stor…0001"
    assert_select "#install_manual[hidden] pre", text: /GoodSorcery\.configure/
    assert_select "#install_env[hidden] pre", text: /GOODSORCERY_ENV=production/
    assert_select "*", text: /Reveal your key under/
    assert_select "pre", text: /bin\/rails goodsorcery:test/
  end

  test "Copy takes a placeholder instead of the masked key" do
    get project_setup_path(projects(:storefront))

    pre = css_select("#install_generator pre").first.dup
    pre.css("[data-clipboard-skip]").each(&:remove) # what clipboard_controller.js copies
    assert_equal "bundle add goodsorcery\nbin/rails generate goodsorcery:install YOUR_PRODUCTION_KEY", pre.text.strip
    assert_select "#install_env pre [hidden]", text: "YOUR_PRODUCTION_KEY"
  end

  test "the page never contains a full token" do
    get project_setup_path(projects(:storefront))

    FIXTURE_TOKENS.each_value { |token| assert_not_includes response.body, token }
  end

  test "self-hosted instances point config.endpoint at this instance" do
    get project_setup_path(projects(:storefront))

    assert_select "#install_manual pre", text: %r{config\.endpoint\s+= "http://www\.example\.com"}
    assert_select "#install_env pre", text: %r{GOODSORCERY_ENDPOINT=http://www\.example\.com}
    assert_select "aside code", text: %(config.endpoint = "http://www.example.com")
  end

  test "lists api keys with reveal and rotate" do
    get project_setup_path(projects(:storefront))

    production = api_keys(:storefront_production)
    staging = api_keys(:storefront_staging)
    assert_select "turbo-frame##{dom_id(production)}" do
      assert_select ".chip", "default"
      assert_select "turbo-frame##{dom_id(production, :token)} code", text: /\Ags_live_Stor.*0001\z/
      assert_select "a[href=?]", project_api_key_reveal_path(projects(:storefront), production), text: "Reveal"
      assert_select "form[action=?] button", project_api_key_rotation_path(projects(:storefront), production), text: "Rotate…"
      assert_select "form[data-turbo-confirm]"
      assert_select "*", text: /Created .* by Philip · last used 2 min ago/
    end
    assert_select "turbo-frame##{dom_id(staging)}" do
      assert_select ".chip", count: 0
      assert_select "*", text: /never used/
    end
    assert_select "form[action=?] input[name=?]", project_api_keys_path(projects(:storefront)), "api_key[environment]"
  end

  test "subscribes to the setup stream and disables the turbo snapshot cache" do
    get project_setup_path(projects(:storefront))

    assert_select "turbo-cable-stream-source[channel=AuthorizedStreamsChannel]"
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "settings nav has setup and general only" do
    get project_setup_path(projects(:storefront))

    assert_select "nav[aria-label='Project settings'] a", count: 2
    assert_select "nav[aria-label='Project settings'] a[aria-current=page]", "Setup & API keys"
  end

  test "has no inline styles" do
    get project_setup_path(projects(:marketing))

    assert_no_match(/style="/, response.body)
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    get project_setup_path(projects(:storefront))

    assert_response :not_found
  end
end
