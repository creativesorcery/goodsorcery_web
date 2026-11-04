require "test_helper"

class UptimeCheckTest < ActiveSupport::TestCase
  test "error labels for every kind, shared by the UI and emails" do
    assert_equal "Timed out after 10 s", UptimeCheck.error_label("timeout")
    assert_equal "DNS lookup failed", UptimeCheck.error_label("dns_failure")
    assert_equal "Connection refused", UptimeCheck.error_label("connection_refused")
    assert_equal "TLS handshake failed", UptimeCheck.error_label("tls_error")
    assert_equal "HTTP 503", UptimeCheck.error_label("http_status", 503)
    assert_equal "Address not allowed", UptimeCheck.error_label("blocked_address")
    assert_equal "Connection failed", UptimeCheck.error_label("connection_error")
    assert_nil UptimeCheck.error_label(nil)
    assert_equal UptimeCheck::ERROR_KINDS.sort, [ *UptimeProbe::ERROR_KINDS.keys, "http_status" ].sort
  end

  test "the instance label and validations" do
    assert_equal "HTTP 503", uptime_checks(:storefront_api_c0).error_label
    assert_nil uptime_checks(:storefront_home_c0).error_label
    assert_not UptimeCheck.new(uptime_monitor: uptime_monitors(:storefront_home), checked_at: Time.current, status: "up", error_kind: "nope").valid?
  end

  test "recent orders newest first" do
    assert_equal uptime_checks(:storefront_home_c0), uptime_monitors(:storefront_home).checks.recent.first
  end

  test "response_series averages up checks in 15-minute buckets" do
    monitor = uptime_monitors(:storefront_api)
    series = UptimeCheck.response_series(monitor)

    assert series.size.between?(3, 5)
    assert_equal series.map(&:first).sort, series.map(&:first)
    assert series.all? { |time, average| (time.to_i % 15.minutes.to_i).zero? && average.between?(90, 102) }
    assert_empty UptimeCheck.response_series(uptime_monitors(:billing_checkout))
  end

  test "response_series takes one query" do
    monitor = uptime_monitors(:storefront_home)

    assert_queries_count(1) { UptimeCheck.response_series(monitor) }
  end
end
