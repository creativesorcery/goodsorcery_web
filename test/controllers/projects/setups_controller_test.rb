require "test_helper"

class Projects::SetupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alex)
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

  test "a listening project keeps the MCP card out of the rail until the first event" do
    get project_setup_path(projects(:marketing))

    assert_select "aside > ##{dom_id(projects(:marketing), :setup_mcp)}[hidden]:empty"
    assert_no_match(/Use it from your AI assistant/, response.body)
  end

  test "a connected project shows the MCP card first in the rail, linking to the MCP page" do
    get project_setup_path(projects(:storefront))

    assert_select "aside > ##{dom_id(projects(:storefront), :setup_mcp)}:first-child:not([hidden])" do
      assert_select "div", text: "Use it from your AI assistant"
      assert_select "p", text: /Claude Code, Codex, Cursor or VS Code can read this app's issues, uptime and performance/
      assert_select "a[href=?]", access_tokens_path, text: "Set up MCP →"
    end
  end

  %w[ruby rust].each do |platform|
    test "connected #{platform} apps show the same MCP card" do
      projects(:storefront).update!(platform:)

      get project_setup_path(projects(:storefront))

      assert_select "aside > ##{dom_id(projects(:storefront), :setup_mcp)} a[href=?]", access_tokens_path, text: "Set up MCP →"
    end
  end

  test "install tabs show only the masked default key" do
    get project_setup_path(projects(:storefront))

    api_key = api_keys(:storefront_production)
    assert_select "[role=tab]", count: 3
    assert_select "[role=tab][aria-selected=true]", "Generator"
    assert_select "#install_generator pre", text: /bundle add goodsorcery/
    assert_select "#install_generator pre [data-clipboard-skip]", text: "gs_live_Stor…0001"
    assert_select "#install_manual[hidden] pre", text: /GoodSorcery\.configure/
    assert_select "#install_manual pre", text: /plugin "goodsorcery"/, count: 0
    assert_select "#install_manual pre", text: /config\.api_key\s+= Rails\.application\.credentials\.dig\(:goodsorcery, :api_key\)/
    assert_select "#install_manual pre", text: /config\.environment\s+= Rails\.env/
    assert_select "#install_generator p", text: /bin\/rails goodsorcery:verify/
    assert_select "#install_generator p", text: /plugin "goodsorcery"/, count: 0
    assert_select "#install_env[hidden] pre", text: /GOODSORCERY_ENV=production/
    assert_select "#install_env p", count: 0
    assert_select "*", text: /Reveal your key under/
    assert_select "pre", text: /bin\/rails goodsorcery:test/
  end

  test "Copy takes a placeholder instead of the masked key" do
    get project_setup_path(projects(:storefront))

    pre = css_select("#install_generator pre").first.dup
    pre.css("[data-clipboard-skip]").each(&:remove) # what clipboard_controller.js copies
    assert_equal "bundle add goodsorcery\nbin/rails generate goodsorcery:install --api-key=YOUR_PRODUCTION_KEY", pre.text.strip
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

  test "rails apps show how to turn on performance monitoring, off by default" do
    get project_setup_path(projects(:storefront))

    assert_select "#install_manual pre", text: /# Performance monitoring: response times, slow endpoints, traces of slow requests\.\s+# config\.performance_monitoring = true/
    assert_select "#install_generator p", text: /uncomment\s+config\.performance_monitoring = true/
  end

  test "rails apps number two steps and keep the rails side panel" do
    get project_setup_path(projects(:storefront))

    assert_equal [ "i.Add the gem", "ii.Cast a test error", "API keys" ], step_headings
    assert_select "#hook_rack", count: 0
    assert_select "pre", text: /rake goodsorcery:test/, count: 0
    assert_select "aside", text: /Rails\.application\.config\.filter_parameters/
    assert_select "aside", text: /current_user/
  end

  test "ruby apps get the plain ruby install without generator or rails lines" do
    projects(:marketing).update!(platform: "ruby")

    get project_setup_path(projects(:marketing))

    assert_select "[role=tab]", text: "Generator", count: 0
    assert_select "#install_generator", count: 0
    assert_select "[aria-label='Install method'] [role=tab]", count: 2
    assert_select "[role=tab][aria-selected=true][aria-controls=install_manual]", "Manual"
    assert_select "#install_manual:not([hidden]) pre", text: /bundle add goodsorcery/
    assert_select "#install_manual pre [data-clipboard-skip]", text: "gs_live_Mark…0001"
    assert_select "#install_manual pre", text: /require "goodsorcery"\s+GoodSorcery\.configure do \|config\|/
    assert_select "#install_manual pre", text: /config\.api_key\s+= ENV\["GOODSORCERY_API_KEY"\]/
    assert_select "#install_manual pre .tok-c", text: /# config\.environment = "production"\s+# default: GOODSORCERY_ENV, RACK_ENV or APP_ENV/
    assert_no_match(/ENV\.fetch\("RACK_ENV"/, response.body)
    assert_select "#install_manual pre", text: /config\.filter_params \+= %i\[card_token ssn\]/
    assert_select "#install_manual pre", text: %r{config\.endpoint\s+= "http://www\.example\.com"}
    assert_select "#install_env[hidden] pre", text: %r{GOODSORCERY_ENV=production\s+GOODSORCERY_ENDPOINT=http://www\.example\.com}
    assert_select "#install_env p", text: /add require "goodsorcery" at boot/
    assert_no_match(/bin\/rails|generate goodsorcery|Rails\.application|Rails\.env|credentials/, response.body)
  end

  test "ruby apps copy a placeholder instead of the masked key" do
    projects(:marketing).update!(platform: "ruby")

    get project_setup_path(projects(:marketing))

    pre = css_select("#install_manual pre").first.dup
    pre.css("[data-clipboard-skip]").each(&:remove)
    assert_equal "bundle add goodsorcery\nexport GOODSORCERY_API_KEY=YOUR_PRODUCTION_KEY", pre.text.strip
  end

  test "ruby apps hook in rack, sidekiq, rake and notify, then test with rake" do
    projects(:marketing).update!(platform: "ruby")

    get project_setup_path(projects(:marketing))

    assert_equal [ "i.Add the gem", "ii.Hook it in", "iii.Cast a test error", "API keys" ], step_headings
    assert_select "#hook_rack:not([hidden]) pre", text: /use GoodSorcery::Rack::Middleware/
    assert_select "#hook_sidekiq[hidden] pre", text: /require "goodsorcery\/integrations\/sidekiq"\s+# GoodSorcery::Integrations::Sidekiq\.install/
    assert_select "#hook_rake[hidden] pre", text: /require "goodsorcery\/tasks"/
    assert_select "#hook_notify[hidden] pre", text: /GoodSorcery\.notify\(e, context: \{ order_id: order\.id \}\)/
    assert_select "pre", text: /\$ bundle exec rake goodsorcery:test/
  end

  test "ruby side panel makes no rails-only claims and keeps self-hosting" do
    projects(:marketing).update!(platform: "ruby")

    get project_setup_path(projects(:marketing))

    assert_select "aside", text: /Rack and Sinatra requests, Sidekiq jobs and rake tasks/
    assert_select "aside", text: /Scrubbed by default/
    assert_select "aside", text: /filter_parameters|current_user|ActiveSupport|ActiveJob/, count: 0
    assert_select "aside code", text: %(config.endpoint = "http://www.example.com")
  end

  test "hosted instances keep the gem's default endpoint on the ruby page" do
    projects(:marketing).update!(platform: "ruby")

    with_hosted_mode { get project_setup_path(projects(:marketing)) }

    assert_select "#install_manual pre", text: /# config\.endpoint = "https:\/\/errors\.yourco\.internal"  # self-hosted/
    assert_select "#install_env pre", text: /GOODSORCERY_ENDPOINT/, count: 0
  end

  test "rust apps add the crate, init from env and hook in axum, with no Ruby lines" do
    projects(:marketing).update!(platform: "rust")

    get project_setup_path(projects(:marketing))

    assert_equal [ "i.Add the crate", "ii.Hook it in", "iii.Cast a test error", "API keys" ], step_headings
    assert_select "#setup_hero_project_#{projects(:marketing).id} ol li[aria-current=step]", text: /Install the crate/
    assert_select "h1 + p", text: /Add the crate, drop in your key/
    assert_select "[aria-label='Install method'] [role=tab]", count: 2
    assert_select "[role=tab][aria-selected=true][aria-controls=install_cargo]", "Cargo"
    assert_select "#install_cargo pre", text: %r{\$ cargo add goodsorcery --git https://github\.com/creativesorcery/goodsorcery-rust\s+\$ export GOODSORCERY_API_KEY=gs_live_Mark…0001}
    assert_select "#install_cargo pre", text: %r{export GOODSORCERY_ENDPOINT=http://www\.example\.com}
    assert_select "#install_cargo pre", text: /let _guard = goodsorcery::init\(\s+goodsorcery::Config::from_env\(\)/
    assert_select "#install_cargo pre .tok-c", text: "// .performance_monitoring(true)"
    assert_select "#install_env[hidden] pre", text: %r{GOODSORCERY_API_KEY=.*GOODSORCERY_ENV=production\s+GOODSORCERY_ENDPOINT=http://www\.example\.com}m
    assert_select "#hook_axum:not([hidden]) pre", text: /\.layer\(goodsorcery::axum::layer\(\)\);/
    assert_select "#hook_capture[hidden] pre", text: /goodsorcery::capture_error\(&err\);/
    assert_select "pre", text: /goodsorcery::capture_error\(&std::io::Error::other\("Good Sorcery test error"\)\);/
    assert_select "aside", text: /Panics anywhere in the process/
    assert_select "aside code", text: "GOODSORCERY_ENDPOINT=http://www.example.com"
    assert_select "aside", text: /Same crate, same UI/
    assert_no_match(/bundle|GoodSorcery\.|config\.endpoint|rake|Rails|\bgem\b/, response.body)
  end

  test "rust apps copy a placeholder instead of the masked key" do
    projects(:marketing).update!(platform: "rust")

    get project_setup_path(projects(:marketing))

    pre = css_select("#install_cargo pre").first.dup
    pre.css("[data-clipboard-skip]").each(&:remove)
    assert_equal "cargo add goodsorcery --git https://github.com/creativesorcery/goodsorcery-rust\nexport GOODSORCERY_API_KEY=YOUR_PRODUCTION_KEY\nexport GOODSORCERY_ENDPOINT=http://www.example.com",
                 pre.text.strip
  end

  test "hosted instances keep the crate's default endpoint on the rust page" do
    projects(:marketing).update!(platform: "rust")

    with_hosted_mode { get project_setup_path(projects(:marketing)) }

    assert_select "#install_cargo pre", text: /export GOODSORCERY_ENDPOINT/, count: 0
    assert_select "#install_env pre", text: /GOODSORCERY_ENDPOINT/, count: 0
  end

  test "lists api keys with reveal and rotate" do
    get project_setup_path(projects(:storefront))

    production = api_keys(:storefront_production)
    staging = api_keys(:storefront_staging)
    assert_select "turbo-frame##{dom_id(production)}" do
      assert_select "span[title=?] .chip", "The install steps on this page use this key", text: "used in setup"
      assert_select "span.bg-coral-500[aria-hidden=true]"
      assert_select "turbo-frame##{dom_id(production, :token)} code", text: /\Ags_live_Stor.*0001\z/
      assert_select "a[href=?]", project_api_key_reveal_path(projects(:storefront), production), text: "Reveal"
      assert_select "form[action=?] button", project_api_key_rotation_path(projects(:storefront), production), text: "Rotate…"
      assert_select "form[data-turbo-confirm]"
      assert_select "*", text: /Created .* by Alex · last used 2 min ago/
    end
    assert_select "turbo-frame##{dom_id(staging)}" do
      assert_select ".chip", count: 0
      assert_select "span.bg-lilac-400[aria-hidden=true]"
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

  test "settings nav has setup, general and alerts" do
    get project_setup_path(projects(:storefront))

    assert_select "nav[aria-label='Project settings'] a", count: 3
    assert_select "nav[aria-label='Project settings'] a[href=?]", project_alerts_path(projects(:storefront)), "Alerts"
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

  private
    # "i.Add the gem": the step number and title of each panel, in page order.
    def step_headings
      css_select("section h2").map { |heading| heading.text.squish }
    end
end
