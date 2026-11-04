require "test_helper"
require_relative "../test_helpers/uptime_test_helper"

class UptimeAlertJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include UptimeTestHelper

  setup { @incident = uptime_incidents(:storefront_api_outage) }

  test "runs on the alerts queue and delivers the incident's alert" do
    assert_equal "alerts", UptimeAlertJob.new.queue_name

    assert_enqueued_emails(2) { UptimeAlertJob.perform_now(@incident.id, "monitor_down") }
  end

  test "drops a missing incident (its monitor was deleted)" do
    monitor = @incident.uptime_monitor
    id = @incident.id
    monitor.destroy!

    assert_no_enqueued_emails { assert_nothing_raised { UptimeAlertJob.perform_now(id, "monitor_down") } }
  end

  test "alert_later enqueues the incident id and the kind only" do
    assert_enqueued_with(job: UptimeAlertJob, args: [ @incident.id, "monitor_down" ], queue: "alerts") do
      @incident.uptime_monitor.alert_later(@incident, "monitor_down")
    end
  end

  test "a check that takes a monitor down alerts, and one that brings it back alerts again, URL never in job args" do
    monitor = uptime_monitors(:storefront_home)

    with_fake_probe(down_result("timeout"), down_result("timeout")) { UptimeCheckJob.perform_now(monitor.id) }
    incident = monitor.incidents.open.sole
    assert_enqueued_with(job: UptimeAlertJob, args: [ incident.id, "monitor_down" ])

    travel UptimeMonitor::RECHECK_GAP + 1.second do
      with_fake_probe(up_result) { UptimeCheckJob.perform_now(monitor.id) }
    end
    assert_enqueued_with(job: UptimeAlertJob, args: [ incident.id, "monitor_recovered" ])

    serialized = enqueued_jobs.inspect
    assert_not_includes serialized, SECRET
    assert_not_includes serialized, "storefront.example"
  end

  test "down then recovered: the same people get both emails, once each" do
    perform_enqueued_jobs(only: UptimeAlertJob) do
      UptimeAlertJob.perform_later(@incident.id, "monitor_down")
      @incident.update_columns(resolved_at: Time.current)
      UptimeAlertJob.perform_later(@incident.id, "monitor_recovered")
      UptimeAlertJob.perform_later(@incident.id, "monitor_recovered")
    end

    assert_equal 4, enqueued_jobs.count { |job| job["job_class"] == "ActionMailer::MailDeliveryJob" }
    assert_equal 2, AlertDelivery.where(dedupe_key: "monitor_recovered:#{@incident.id}").count
  end
end
