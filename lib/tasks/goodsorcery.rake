namespace :goodsorcery do
  desc "Delete occurrences past each project's retention period, hourly issue counts older than 31 days, project counts older than 90 days, old uptime history and performance data past its retention (run daily)"
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

  desc "Fit uptime monitors (pause, resume, re-interval) and each app's error retention to each account's entitlements (run after switching GOODSORCERY_HOSTED on or off, or editing config/entitlements.yml)"
  task fit_entitlements: :environment do
    count = 0
    Account.find_each do |account|
      account.fit_to_entitlements
      count += 1
    end
    puts "Fitted the uptime monitors and app retention of #{count} account(s) to their entitlements."
  end

  desc "Alias of goodsorcery:fit_entitlements, which also fits each app's error retention"
  task fit_uptime_monitors: :environment do
    Rake::Task["goodsorcery:fit_entitlements"].execute
  end
end
