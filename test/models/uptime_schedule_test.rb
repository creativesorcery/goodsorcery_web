require "test_helper"

class UptimeScheduleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @now = Time.utc(2026, 11, 3, 12, 0, 0.25)
    UptimeMonitor.update_all(next_check_at: @now + 1.hour)
  end

  def make_due(*monitors, at: @now - 1.second)
    UptimeMonitor.where(id: monitors.map(&:id)).update_all(next_check_at: at)
  end

  test "claims due monitors and bumps next_check_at from their own minute by the interval" do
    make_due(uptime_monitors(:storefront_home), uptime_monitors(:storefront_api))

    ids = UptimeSchedule.new(now: @now).claim_batch

    assert_equal [ uptime_monitors(:storefront_home).id, uptime_monitors(:storefront_api).id ].sort, ids.sort
    assert_equal Time.utc(2026, 11, 3, 12, 9), uptime_monitors(:storefront_home).reload.next_check_at
    assert_equal Time.utc(2026, 11, 3, 12, 4), uptime_monitors(:storefront_api).reload.next_check_at
  end

  test "late claims keep each monitor on its own schedule instead of bunching them up" do
    home, api = uptime_monitors(:storefront_home), uptime_monitors(:storefront_api)
    api.update_columns(interval_minutes: 10)
    make_due(home, at: Time.utc(2026, 11, 3, 12, 3, 30))
    make_due(api, at: Time.utc(2026, 11, 3, 12, 7))

    UptimeSchedule.new(now: Time.utc(2026, 11, 3, 12, 20, 5)).claim_batch

    assert_equal Time.utc(2026, 11, 3, 12, 23), home.reload.next_check_at
    assert_equal Time.utc(2026, 11, 3, 12, 27), api.reload.next_check_at
  end

  test "a claim exactly on the due minute moves one interval on" do
    make_due(uptime_monitors(:storefront_home), at: Time.utc(2026, 11, 3, 12))

    UptimeSchedule.new(now: Time.utc(2026, 11, 3, 12, 0, 0.4)).claim_batch

    assert_equal Time.utc(2026, 11, 3, 12, 10), uptime_monitors(:storefront_home).reload.next_check_at
  end

  test "a second claim gets nothing" do
    make_due(uptime_monitors(:storefront_home))
    schedule = UptimeSchedule.new(now: @now)

    assert_equal 1, schedule.claim_batch.size
    assert_empty schedule.claim_batch
  end

  test "skips paused monitors and ones not yet due" do
    make_due(uptime_monitors(:storefront_home), uptime_monitors(:billing_checkout))
    uptime_monitors(:billing_checkout).update_columns(paused_at: @now)

    assert_equal [ uptime_monitors(:storefront_home).id ], UptimeSchedule.new(now: @now).claim_batch
  end

  test "enqueues one check job per due monitor, with ids only, in batches" do
    monitors = 3.times.map { |i| projects(:storefront).uptime_monitors.create!(name: "M#{i}", url: "https://m#{i}.example/") }
    make_due(*monitors, uptime_monitors(:storefront_home), uptime_monitors(:umbrella_site))
    statements = count_claims { assert_equal 5, UptimeSchedule.new(now: @now, batch: 2).enqueue_due }

    assert_equal 3, statements
    jobs = enqueued_jobs.select { |job| job["job_class"] == "UptimeCheckJob" }
    assert_equal 5, jobs.size
    assert jobs.all? { |job| job["arguments"].sole.is_a?(Integer) && job["queue_name"] == "uptime" }
    assert_not_includes jobs.inspect, "uptime-fixture-secret"
  end

  test "the query count doesn't grow with the number of due monitors" do
    make_due(uptime_monitors(:storefront_home))
    one = count_queries { UptimeSchedule.new(now: @now).enqueue_due }
    5.times { |i| projects(:storefront).uptime_monitors.create!(name: "N#{i}", url: "https://n#{i}.example/") }
    UptimeMonitor.update_all(next_check_at: @now - 1.second)
    many = count_queries { assert_equal 9, UptimeSchedule.new(now: @now).enqueue_due }

    assert_equal 1, one
    assert_equal one, many
  end

  test "the claim reads the due partial index" do
    sql = UptimeMonitor.sanitize_sql([ UptimeSchedule::CLAIM_SQL.sub(/\AUPDATE.*?WHERE id IN \(/m, "").delete_suffix(") RETURNING id"),
                                       { now: @now, batch: 500 } ])
    plan = UptimeMonitor.transaction do
      UptimeMonitor.connection.execute("SET LOCAL enable_seqscan = off")
      UptimeMonitor.connection.select_values("EXPLAIN #{sql}").join("\n")
    end

    assert_includes plan, "index_uptime_monitors_due"
  end

  private
    def count_queries(&block)
      count = 0
      callback = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("SAVEPOINT", "RELEASE") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
      count
    end

    def count_claims(&block)
      count = 0
      callback = ->(*, payload) { count += 1 if payload[:sql].start_with?("UPDATE uptime_monitors SET next_check_at") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
      count
    end
end
