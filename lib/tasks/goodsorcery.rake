namespace :goodsorcery do
  desc "Delete occurrences past each project's retention period, hourly issue counts older than 31 days, project counts older than 90 days and old uptime history (run daily)"
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

  desc "Pause, resume and re-interval uptime monitors to fit each account's entitlements (run after switching hosted mode on or editing config/entitlements.yml)"
  task fit_uptime_monitors: :environment do
    count = 0
    Account.find_each do |account|
      account.fit_uptime_monitors_to_entitlements
      count += 1
    end
    puts "Fitted the uptime monitors of #{count} account(s) to their entitlements."
  end
end
