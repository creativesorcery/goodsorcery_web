# Every minute (config/schedule.yml): claims the monitors that are due and
# enqueues one UptimeCheckJob per monitor (UptimeSchedule).
#
# On the default queue, so scheduling never waits behind slow checks.
class ScheduleUptimeChecksJob < ApplicationJob
  queue_as :default

  def perform
    UptimeSchedule.enqueue_due
  end
end
