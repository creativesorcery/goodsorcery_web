# Holds every project to Occurrence::RETAINED_PER_PROJECT stored occurrences
# (see Ingest::OccurrenceCap). Scheduled by sidekiq-cron in config/schedule.yml.
# Deleting the same rows twice is harmless, so overlapping runs are safe.
class CapStoredOccurrencesJob < ApplicationJob
  queue_as :default

  def perform
    Ingest::OccurrenceCap.enforce_all
  end
end
