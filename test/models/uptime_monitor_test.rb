require "test_helper"
require_relative "../test_helpers/uptime_test_helper"

class UptimeMonitorTest < ActiveSupport::TestCase
  include UptimeTestHelper

  def build(project = projects(:storefront), **attributes)
    project.uptime_monitors.new({ url: "https://shop.example/up", interval_minutes: 10 }.merge(attributes))
  end

  test "fixtures are valid" do
    UptimeMonitor.find_each { |monitor| assert monitor.valid?, monitor.errors.full_messages.to_sentence }
  end

  test "the name defaults to the host, capped at 60 characters" do
    monitor = build(name: " ")
    monitor.validate

    assert_equal "shop.example", monitor.name
    long = build(name: nil, url: "https://#{'a' * 63}.#{'b' * 20}.example/")
    long.validate
    assert_equal 60, long.name.length
  end

  test "name is 1..60 characters, squished" do
    assert_equal "Shop home", build(name: "  Shop   home ").tap(&:validate).name
    assert_not build(name: "x" * 61).valid?
  end

  test "the URL must be public http(s), and errors never echo it" do
    [ "", "ftp://shop.example/", "http://localhost:3000/", "http://169.254.169.254/latest", "http://10.0.0.1/?token=#{SECRET}" ].each do |url|
      monitor = build(url:)
      assert_not monitor.valid?, url
      assert monitor.errors.include?(:url)
      assert monitor.errors.full_messages.none? { |message| message.include?(SECRET) || message.include?("10.0.0.1") }
    end
    assert_includes build(url: "gopher://x/").tap(&:validate).errors[:url], UptimeMonitor::URL_MESSAGE
  end

  test "the URL is normalised and stored encrypted" do
    monitor = build(url: " https://Shop.Example/up?token=#{SECRET}#frag ").tap(&:save!)

    assert_equal "https://shop.example/up?token=#{SECRET}", monitor.reload.url
    raw = UptimeMonitor.connection.select_value(UptimeMonitor.where(id: monitor.id).select(:url).to_sql)
    assert_not_includes raw, SECRET
    assert_not_includes raw, "shop.example"
  end

  test "interval must be one of the supported intervals" do
    assert_not build(interval_minutes: 2).valid?
    assert_not build(interval_minutes: "often").valid?
    UptimeMonitor::INTERVALS.each { |minutes| assert build(interval_minutes: minutes).valid?, minutes }
  end

  test "self-hosted allows every interval and any number of monitors" do
    with_hosted_mode(false) do
      assert build(interval_minutes: 1).save
      assert build(name: "Another", interval_minutes: 1).save
    end
  end

  test "hosted rejects intervals the account isn't entitled to" do
    with_hosted_mode do
      monitor = build(projects(:umbrella_app), interval_minutes: 1)

      assert_not monitor.valid?
      assert_includes monitor.errors[:interval_minutes], "isn't available on this account"
      assert build(projects(:umbrella_app), interval_minutes: 5).valid?
    end
  end

  test "hosted only checks the interval when it changes" do
    monitor = uptime_monitors(:storefront_api) # 5 minutes; acme's hosted default allows 10 and 60
    with_hosted_mode do
      assert monitor.update(name: "Renamed API")
      assert_not monitor.update(interval_minutes: 1)
      assert monitor.reload.update(interval_minutes: 60)
    end
  end

  test "hosted counts only the monitors of the same app against the limit" do
    second_app = with_hosted_mode(false) { accounts(:umbrella).projects.create!(name: "Umbrella API") }

    with_hosted_mode do
      2.times { |i| assert build(projects(:umbrella_app), name: "Site #{i}", interval_minutes: 5).save }
      over = build(projects(:umbrella_app), name: "One too many", interval_minutes: 5)
      with_upgrade_url { assert_not over.save }
      assert_equal [ "This app has reached its limit of 3 monitors." ], over.errors[:base]

      3.times { |i| assert build(second_app, name: "API #{i}", interval_minutes: 5).save, "another app has its own 3" }
      assert_not build(second_app, name: "API 4", interval_minutes: 5).save
    end
    assert_equal [ 3, 3 ], [ projects(:umbrella_app), second_app ].map { it.uptime_monitors.count }
  end

  test "hosted defaults apply per app when the account stores no limit" do
    with_hosted_mode do
      monitor = build(projects(:storefront)) # storefront already has 2 monitors, over the default of 1 per app

      with_upgrade_url { assert_not monitor.save }
      assert_equal [ "This app has reached its limit of 1 monitor." ], monitor.errors[:base]

      assert build(projects(:marketing)).save, "marketing, in the same account, has no monitor yet"
      assert_not build(projects(:marketing), name: "Second").save
    end
  end

  test "without an upgrade URL, the limit error says more are coming soon" do
    with_hosted_mode do
      monitor = build(projects(:storefront))

      with_upgrade_url(nil) { assert_not monitor.save }
      assert_equal [ "Cannot add more yet, but it's coming soon" ], monitor.errors[:base]
    end
  end

  test "a stored max_monitors of null means no cap" do
    accounts(:umbrella).update_entitlements!("uptime_intervals" => [ 5, 10, 60 ], "max_monitors" => nil)
    with_hosted_mode do
      4.times { |i| assert build(projects(:umbrella_app), name: "Site #{i}").save }
    end
  end

  test "creating, or changing the URL or interval, schedules a check now" do
    freeze_time
    monitor = build.tap(&:save!)
    assert_equal Time.current, monitor.next_check_at

    monitor.update_columns(next_check_at: 1.hour.from_now)
    monitor.update!(name: "Renamed")
    assert_equal 1.hour.from_now, monitor.next_check_at

    monitor.update!(interval_minutes: 60)
    assert_equal Time.current, monitor.next_check_at
    monitor.update_columns(next_check_at: 1.hour.from_now)
    monitor.update!(url: "https://shop.example/health")
    assert_equal Time.current, monitor.next_check_at
  end

  test "host, labels and predicates" do
    monitor = uptime_monitors(:storefront_home)

    assert_equal "storefront.example", monitor.host
    assert_equal "Every 10 minutes", monitor.interval_label
    assert_equal "Every minute", build(interval_minutes: 1).interval_label
    assert_not monitor.paused?
    assert monitor.checked_recently?(monitor.last_checked_at + 29.seconds)
    assert_not monitor.checked_recently?(monitor.last_checked_at + 31.seconds)
    assert_not uptime_monitors(:billing_checkout).checked_recently?
  end

  test "open_incident" do
    assert_equal uptime_incidents(:storefront_api_outage), uptime_monitors(:storefront_api).open_incident
    assert_nil uptime_monitors(:storefront_home).open_incident
  end

  test "due and active scopes skip paused monitors" do
    UptimeMonitor.update_all(next_check_at: 1.minute.ago)
    uptime_monitors(:billing_checkout).update_columns(paused_at: Time.current)

    assert_equal 3, UptimeMonitor.due.count
    assert_not_includes UptimeMonitor.active, uptime_monitors(:billing_checkout)
    assert_equal 0, UptimeMonitor.due(2.minutes.ago).count
  end

  test "deleting a monitor deletes its history" do
    monitor = uptime_monitors(:storefront_api)

    monitor.destroy!

    assert_equal 0, UptimeCheck.where(uptime_monitor_id: monitor.id).count
    assert_equal 0, UptimeHourlyCount.where(uptime_monitor_id: monitor.id).count
    assert_equal 0, UptimeIncident.where(uptime_monitor_id: monitor.id).count
  end

  test "the URL never reaches the log when a monitor is created" do
    log = capture_log { build(url: "https://shop.example/up?token=#{SECRET}").save! }

    assert_includes log, "INSERT INTO \"uptime_monitors\""
    assert_not_includes log, SECRET
  end

  test "url is filtered from request parameter logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal "[FILTERED]", filter.filter("uptime_monitor" => { "url" => "https://x.example/?token=#{SECRET}" }).dig("uptime_monitor", "url")
  end
end
