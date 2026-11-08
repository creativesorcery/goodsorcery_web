# Builds the apm_minute_stats and apm_hourly_stats fixtures from one
# per-minute profile per transaction, so minute rows (the last 2 hours) and
# hourly rows (the last 25 hours) always agree. checkout_create is Slower:
# its requests in the last 60 minutes land around 1 s instead of ~220 ms.
module ApmFixtureStats
  MINUTE_ROWS = 120
  HOURS = 25

  NORMAL_CHECKOUT = { count: 4, duration_ms: 980.0, buckets: [ [ 15, 3, 300.0, 150.0, 120.0, 90.0 ], [ 16, 1, 160.0, 80.0, 40.0, 40.0 ] ] }.freeze
  SLOW_CHECKOUT = { count: 4, duration_ms: 4300.0, buckets: [ [ 19, 3, 1500.0, 900.0, 300.0, 300.0 ], [ 20, 1, 700.0, 400.0, 100.0, 100.0 ] ] }.freeze
  PRODUCTS = { count: 10, duration_ms: 860.0, buckets: [ [ 12, 8, 200.0, 0.0, 260.0, 100.0 ], [ 14, 2, 120.0, 0.0, 120.0, 60.0 ] ] }.freeze
  PLACE_ORDER = { count: 2, duration_ms: 1000.0, buckets: [ [ 17, 2, 500.0, 300.0, 0.0, 200.0 ] ],
                  queue_wait: [ [ 11, 2 ] ], queue_wait_ms: 100.0 }.freeze
  BILLING = { count: 1, duration_ms: 100.0, buckets: [ [ 13, 1, 50.0, 0.0, 30.0, 20.0 ] ] }.freeze
  UMBRELLA = { count: 2, duration_ms: 60.0, buckets: [ [ 10, 2, 30.0, 0.0, 20.0, 10.0 ] ] }.freeze

  LABELS = %w[checkout_create products_show place_order_job storefront_web_total storefront_jobs_total
              billing_invoices umbrella_home].freeze

  # Every APM fixture is placed relative to this one instant, taken once when
  # the test process loads. Tests that read APM data include ApmFixtureClock,
  # which travels to it, so a minute or hour passing between loading the
  # fixtures and running a test can't shift the windows the tests count in.
  # It never falls in the first 15 minutes of an hour: traces sit up to 10
  # minutes before it and must stay in the same (open) hour.
  ANCHOR = Time.current.change(usec: 0).then { it.min < 15 ? it - 15.minutes : it }

  module_function

  def now_minute = TimeSeries.align(ANCHOR, 1.minute)

  def now_hour = TimeSeries.align(ANCHOR, 1.hour)

  # The Distribution of one transaction for the minute `minutes_ago` minutes back.
  def minute(label, minutes_ago)
    case label
    when "checkout_create" then checkout(minutes_ago)
    when "storefront_web_total" then checkout(minutes_ago) + build(PRODUCTS)
    when "products_show" then build(PRODUCTS)
    when "place_order_job", "storefront_jobs_total" then build(PLACE_ORDER)
    when "billing_invoices" then build(BILLING)
    else build(UMBRELLA)
    end
  end

  def checkout(minutes_ago)
    profile = minutes_ago < 60 ? SLOW_CHECKOUT : NORMAL_CHECKOUT
    build(profile.merge(failed: (minutes_ago % 10).zero? ? 1 : 0))
  end

  def build(profile)
    Apm::Distribution.from_buckets(failed: 0, **profile)
  end

  # [[minute, Distribution]] for the last MINUTE_ROWS minutes.
  def minute_rows(label)
    Array.new(MINUTE_ROWS) { |ago| [ now_minute - ago.minutes, minute(label, ago) ] }
  end

  # [[hour, Distribution]] for the last HOURS hours (the current one up to now).
  def hourly_rows(label)
    Array.new(HOURS) do |ago|
      hour = now_hour - ago.hours
      minutes = (0...60).map { hour + it.minutes }.select { it <= now_minute }
      [ hour, minutes.sum(Apm::Distribution.empty) { minute(label, ((now_minute - it) / 60).round) } ]
    end
  end

  # The YAML body of one stats row.
  def columns(distribution)
    { "requests_count" => distribution.count, "failed_count" => distribution.failed,
      "duration_ms_sum" => distribution.duration_ms, "queue_wait_ms_sum" => distribution.queue_wait_ms,
      "bucket_counts" => distribution.counts, "bucket_db_ms" => distribution.db_ms,
      "bucket_http_ms" => distribution.http_ms, "bucket_view_ms" => distribution.view_ms,
      "bucket_ruby_ms" => distribution.ruby_ms, "queue_wait_counts" => distribution.queue_wait_counts }
  end
end
