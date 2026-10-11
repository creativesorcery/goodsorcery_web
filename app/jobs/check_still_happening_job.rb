# Every 5 minutes (config/schedule.yml): enqueues still_happening alerts for
# issues whose trailing-hour events reach their app's threshold.
class CheckStillHappeningJob < ApplicationJob
  queue_as :alerts

  def perform
    StillHappeningCheck.new.alert_hot_issues
  end
end
