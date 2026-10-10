# Re-enqueues inbound events whose processing job was lost (see
# Ingest::StaleEvents). Scheduled by sidekiq-cron in config/schedule.yml;
# bin/rails goodsorcery:requeue_stale does the same by hand. A requeued event
# that was processed in the meantime is discarded, and a duplicate occurrence
# is never inserted, so overlapping runs are safe.
class RequeueStaleEventsJob < ApplicationJob
  queue_as :default

  def perform
    Ingest::StaleEvents.new.requeue
  end
end
