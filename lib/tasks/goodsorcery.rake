namespace :goodsorcery do
  desc "Delete occurrences past each project's retention period, hourly issue counts older than 31 days and project counts older than 90 days (run daily)"
  task prune: :environment do
    Ingest::Retention.new.prune
  end

  desc "Re-enqueue inbound events accepted over 10 minutes ago but never processed (e.g. after a Redis outage)"
  task requeue_stale: :environment do
    puts "Re-enqueued #{Ingest::StaleEvents.new.requeue} stale inbound event(s)."
  end

  desc "Trim each app to its stored occurrence cap, dropping the oldest copies of its most repeated issues first"
  task cap_occurrences: :environment do
    puts "Deleted #{Ingest::OccurrenceCap.enforce_all} occurrence(s) over the per-app cap."
  end
end
