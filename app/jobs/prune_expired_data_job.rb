# Daily retention sweep (see Ingest::Retention). Scheduled by sidekiq-cron in
# config/schedule.yml; bin/rails goodsorcery:prune runs the same sweep by hand.
class PruneExpiredDataJob < ApplicationJob
  queue_as :default

  def perform
    Ingest::Retention.new.prune
  end
end
