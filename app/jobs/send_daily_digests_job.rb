# Hourly (config/schedule.yml): mails each app's daily digest to the members
# whose local time is in the 09:00 hour (DailyDigest).
class SendDailyDigestsJob < ApplicationJob
  queue_as :alerts

  def perform
    DailyDigest.deliver_due
  end
end
