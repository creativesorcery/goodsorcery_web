require "test_helper"
require "rake"

class Account::UptimeMonitoringTest < ActiveSupport::TestCase
  setup do
    freeze_time
    @account = accounts(:umbrella) # stores [5, 10, 60] and 3 monitors
    @site = uptime_monitors(:umbrella_site)
    @second = add_monitor("Second", 1)
    @third = add_monitor("Third", 60)
  end

  def add_monitor(name, interval)
    with_hosted_mode(false) { projects(:umbrella_app).uptime_monitors.create!(name:, url: "https://#{name.downcase}.example/", interval_minutes: interval) }
  end

  test "uptime_monitors spans every app of the account" do
    assert_equal [ uptime_monitors(:storefront_home), uptime_monitors(:storefront_api), uptime_monitors(:billing_checkout) ].sort_by(&:id),
                 accounts(:acme).uptime_monitors.order(:id).to_a
    assert_equal 3, @account.uptime_monitors.count
  end

  test "monitor_limit_reached? counts the whole account" do
    with_hosted_mode do
      assert @account.monitor_limit_reached?
      assert accounts(:acme).monitor_limit_reached?
    end
    with_hosted_mode(false) { assert_not @account.monitor_limit_reached? }
  end

  test "a downgrade moves disallowed intervals and pauses the newest monitors over the limit" do
    with_hosted_mode { @account.update_entitlements!("uptime_intervals" => [ 10, 60 ], "max_monitors" => 1) }

    assert_equal [ 10, 10, 60 ], [ @site, @second, @third ].map { it.reload.interval_minutes }
    assert_nil @site.paused_at
    assert_equal [ Time.current, Time.current ], [ @second.paused_at, @third.paused_at ]
  end

  test "an upgrade resumes paused monitors that fit again, oldest first, and checks them now" do
    with_hosted_mode do
      @account.update_entitlements!("max_monitors" => 1)
      travel 1.hour
      @account.update_entitlements!("max_monitors" => 2)
    end

    assert_not @second.reload.paused?
    assert_equal Time.current, @second.next_check_at
    assert @third.reload.paused?
  end

  test "deleting a monitor frees a place for a paused one" do
    with_hosted_mode do
      @account.update_entitlements!("max_monitors" => 2)
      assert @third.reload.paused?

      @site.destroy!
    end

    assert_not @third.reload.paused?
    assert_not @second.reload.paused?
  end

  test "self-hosted resumes every monitor and leaves intervals alone" do
    with_hosted_mode { @account.update_entitlements!("uptime_intervals" => [ 60 ], "max_monitors" => 0) }
    assert [ @site, @second, @third ].all? { it.reload.paused? }

    with_hosted_mode(false) { @account.fit_uptime_monitors_to_entitlements }

    assert [ @site, @second, @third ].none? { it.reload.paused? }
    assert_equal [ 60, 60, 60 ], [ @site, @second, @third ].map(&:interval_minutes)
  end

  test "a missing key falls back to the hosted defaults when fitting" do
    with_hosted_mode { @account.update_entitlements!({}) } # defaults: [10, 60] and 1 monitor

    assert_equal [ 10, 10, 60 ], [ @site, @second, @third ].map { it.reload.interval_minutes }
    assert_equal [ false, true, true ], [ @site, @second, @third ].map(&:paused?)
  end

  test "unrelated account saves don't refit" do
    UptimeMonitor.where(id: @third.id).update_all(paused_at: 1.day.ago)

    with_hosted_mode { @account.update!(name: "Umbrella Corporation") }

    assert @third.reload.paused?
  end

  test "fitting never touches another account's monitors" do
    with_hosted_mode { @account.update_entitlements!("uptime_intervals" => [ 60 ], "max_monitors" => 0) }

    assert UptimeMonitor.where(project: projects(:storefront)).none?(&:paused?)
    assert_equal 10, uptime_monitors(:storefront_home).reload.interval_minutes
  end

  test "the rake task fits every account" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("goodsorcery:fit_uptime_monitors")
    UptimeMonitor.where(id: @third.id).update_all(paused_at: 1.day.ago)

    assert_output(/Fitted the uptime monitors of 2 account\(s\)/) { Rake::Task["goodsorcery:fit_uptime_monitors"].execute }
    assert_not @third.reload.paused?
  end
end
