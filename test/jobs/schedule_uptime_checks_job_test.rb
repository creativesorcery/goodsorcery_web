require "test_helper"

class ScheduleUptimeChecksJobTest < ActiveJob::TestCase
  test "runs on the uptime queue and enqueues the due checks" do
    UptimeMonitor.update_all(next_check_at: 1.hour.from_now)
    uptime_monitors(:storefront_home).update_columns(next_check_at: 1.minute.ago)

    assert_equal "uptime", ScheduleUptimeChecksJob.new.queue_name
    assert_enqueued_with(job: UptimeCheckJob, args: [ uptime_monitors(:storefront_home).id ], queue: "uptime") do
      ScheduleUptimeChecksJob.perform_now
    end
    assert_enqueued_jobs 1, only: UptimeCheckJob
  end

  test "the uptime queue is in the Sidekiq config" do
    queues = YAML.load(ERB.new(Rails.root.join("config/sidekiq.yml").read).result, permitted_classes: [ Symbol ])[:queues]

    assert_includes queues, [ "uptime", 2 ]
  end
end
