require "test_helper"

class UptimeHelperTest < ActionView::TestCase
  include UptimeHelper, ChipHelper, EntitlementsHelper

  teardown { Current.reset }

  test "status bar colours each hour by its share of up checks, with a title" do
    hour = Time.utc(2026, 10, 3, 14)
    svg = parse(uptime_bar_svg([ [ hour, 0, 0 ], [ hour + 1.hour, 6, 6 ], [ hour + 2.hours, 6, 4 ], [ hour + 3.hours, 6, 1 ] ]))

    none, all, most, few = svg.css("rect")
    assert_equal [ ChartHelper::PAPER, "0.45" ], [ none["fill"], none["opacity"] ]
    assert_equal [ ChartHelper::MINT, "1" ], [ all["fill"], all["opacity"] ]
    assert_equal [ ChartHelper::CORAL, "0.55" ], [ most["fill"], most["opacity"] ]
    assert_equal [ ChartHelper::CORAL, "1" ], [ few["fill"], few["opacity"] ]
    assert_equal "Oct 3, 14:00 · no checks", none.at_css("title").text
    assert_equal "Oct 3, 16:00 · 66.66% up · 6 checks", most.at_css("title").text
    assert_equal "0 0 24 22", svg["viewBox"]
    assert_equal "none", svg["preserveAspectRatio"]
    assert_equal "Last 24 hours: 61.11% up", svg["aria-label"]
  end

  test "the daily bar titles days and labels its period" do
    day = Time.utc(2026, 10, 3)
    svg = parse(uptime_daily_bar_svg([ [ day, 144, 144 ], [ day + 1.day, 0, 0 ] ]))

    assert_equal "Oct 3 · 100% up · 144 checks", svg.at_css("rect title").text
    assert_equal "Last 2 days: 100% up", svg["aria-label"]
  end

  test "an empty bar has no checks" do
    assert_equal "Last 24 hours: no checks", parse(uptime_bar_svg([]))["aria-label"]
  end

  test "percentages round down and drop trailing zeros" do
    assert_equal "100%", uptime_percent(100.0)
    assert_equal "99.99%", uptime_percent(99.9999)
    assert_equal "99.5%", uptime_percent(99.5)
    assert_equal "—", uptime_percent(nil)
  end

  test "response times and durations" do
    assert_equal "212 ms", uptime_ms(212)
    assert_equal "1,840 ms", uptime_ms(1840.4)
    assert_equal "—", uptime_ms(nil)
    assert_equal "40 s", uptime_duration(40)
    assert_equal "14 min", uptime_duration(14.minutes + 5)
    assert_equal "2h 5m", uptime_duration(2.hours + 5.minutes)
    assert_equal "1d 3h", uptime_duration(1.day + 3.hours)
  end

  test "status chips" do
    assert_select_in uptime_status_chip(uptime_monitors(:storefront_home)), ".chip-mint", "Up"
    freeze_time do
      monitor = uptime_monitors(:storefront_api)
      monitor.down_since = 12.minutes.ago
      assert_select_in uptime_status_chip(monitor), ".chip-coral .coral-dot"
      assert_select_in uptime_status_chip(monitor), ".chip-coral", "Down for 12 min"
    end
    assert_select_in uptime_status_chip(uptime_monitors(:billing_checkout)), ".chip-muted", "Pending"
    assert_select_in uptime_status_chip(UptimeMonitor.new(status: "up", paused_at: Time.current)), ".chip-muted", "Paused"
  end

  test "interval options are all open when self-hosted" do
    Current.session = users(:philip).sessions.create!(account: accounts(:acme))

    assert_equal [ [ "Every minute", 1 ], [ "Every 5 minutes", 5 ], [ "Every 10 minutes", 10 ], [ "Every hour", 60 ] ],
      uptime_interval_options
  end

  test "hosted with an upgrade URL, locked interval options say Upgrade to unlock" do
    Current.session = users(:philip).sessions.create!(account: accounts(:acme))

    with_hosted_mode do
      with_upgrade_url do
        assert_equal [ [ "Every minute · Upgrade to unlock", 1, { title: "Upgrade to unlock" } ],
                       [ "Every 5 minutes · Upgrade to unlock", 5, { title: "Upgrade to unlock" } ],
                       [ "Every 10 minutes", 10 ], [ "Every hour", 60 ] ], uptime_interval_options
      end
    end
  end

  test "hosted without an upgrade URL, locked interval options say Coming soon" do
    Current.session = users(:philip).sessions.create!(account: accounts(:acme))

    with_hosted_mode do
      with_upgrade_url(nil) do
        assert_equal [ [ "Every minute · Coming soon", 1, { title: "Coming soon" } ],
                       [ "Every 5 minutes · Coming soon", 5, { title: "Coming soon" } ],
                       [ "Every 10 minutes", 10 ], [ "Every hour", 60 ] ], uptime_interval_options
        assert_equal "Some intervals are coming soon.", uptime_locked_intervals_hint
      end
    end
  end

  test "error sentences name the field and never echo the URL" do
    monitor = UptimeMonitor.new(project: projects(:storefront), url: "http://10.0.0.1/?token=secret", name: "x" * 61)
    monitor.validate

    sentences = uptime_monitor_error_sentences(monitor)
    assert_includes sentences, "URL must be a public http:// or https:// address."
    assert_includes sentences, "Name is too long (maximum is 60 characters)."
    assert(sentences.none? { it.include?("secret") })
  end

  private
    def parse(html) = Nokogiri::HTML5.fragment(html).at_css("svg")

    def assert_select_in(html, selector, text = nil)
      node = Nokogiri::HTML5.fragment(html).at_css(selector)
      assert node, "expected #{selector} in #{html}"
      assert_equal text, node.text if text
    end
end
