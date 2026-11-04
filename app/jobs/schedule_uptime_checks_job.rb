# Every minute (config/schedule.yml): claims the monitors that are due and
# enqueues one UptimeCheckJob per monitor (UptimeSchedule).
class ScheduleUptimeChecksJob < ApplicationJob
  queue_as :uptime

  def perform
    UptimeSchedule.enqueue_due
  end
end
