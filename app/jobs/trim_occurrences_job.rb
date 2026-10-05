# Keeps only the newest Occurrence::RETAINED_PER_ISSUE occurrences of an issue.
# Counters and rollups are unaffected; only stored payloads are dropped.
class TrimOccurrencesJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(issue)
    cutoff_id = issue.occurrences.latest_first.offset(Occurrence::RETAINED_PER_ISSUE).pick(:id)
    issue.occurrences.where(id: ..cutoff_id).in_batches(of: 1_000).delete_all if cutoff_id
  end
end
