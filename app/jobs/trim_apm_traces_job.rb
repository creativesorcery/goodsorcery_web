# Hourly (sidekiq-cron, "3 * * * *"): keeps the 3 slowest traces per
# transaction for each closed hour. Takes no arguments.
class TrimApmTracesJob < ApplicationJob
  queue_as :default

  def perform
    deleted = Apm::TraceTrim.new.trim
    Rails.logger.info { "Trimmed #{deleted} APM trace(s) from closed hours" } if deleted.positive?
  end
end
