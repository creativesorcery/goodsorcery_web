require "test_helper"
require_relative "../../test_helpers/uptime_test_helper"

class UptimeMonitor::BroadcastingTest < ActiveSupport::TestCase
  include ActionCable::TestHelper, UptimeTestHelper

  setup do
    @monitor = uptime_monitors(:storefront_home)
    @project = @monitor.project
  end

  test "broadcast_checked reloads the monitor's list row and detail report" do
    @monitor.broadcast_checked

    row, report = capture_turbo_stream_broadcasts([ @project, :uptime ])
    assert_equal [ "reload_frame", "row_uptime_monitor_#{@monitor.id}", "/projects/storefront/uptime/#{@monitor.id}/row" ],
      %w[action target src].map { row[it] }
    assert_equal [ "reload_frame", "report_uptime_monitor_#{@monitor.id}", "/projects/storefront/uptime/#{@monitor.id}/report" ],
      %w[action target src].map { report[it] }
  end

  test "broadcasts carry no URL, host or name" do
    @monitor.broadcast_checked

    payloads = broadcasts(stream_name_from([ @project, :uptime ]))
    assert_equal 2, payloads.size
    payloads.each do |payload|
      [ SECRET, @monitor.url, @monitor.host, @monitor.name ].each { |secret| assert_not_includes payload, secret }
    end
  end

  test "a check job broadcasts once, on the monitor's app stream only" do
    @monitor.update_columns(last_checked_at: 1.hour.ago)

    with_fake_probe(up_result) { UptimeCheckJob.perform_now(@monitor.id) }

    assert_equal 2, broadcasts(stream_name_from([ @project, :uptime ])).size
    assert_no_turbo_stream_broadcasts [ projects(:billing), :uptime ]
  end
end
