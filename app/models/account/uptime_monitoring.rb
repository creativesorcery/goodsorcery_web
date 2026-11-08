# An account's uptime monitors and keeping them within its entitlements
# (docs/ARCHITECTURE.md §12.3.1). Entitlements are account-level, but
# max_monitors is a limit per app: each app of the account may have that
# many monitors.
#
# Fitting runs after a commit that changes entitlement_values and from
# bin/rails goodsorcery:fit_entitlements (both through
# Account#fit_to_entitlements), and after a monitor is destroyed:
#
# 1. A monitor whose interval isn't allowed moves to the nearest allowed one.
# 2. In each app, the oldest monitors (by id) up to max_monitors run; newer
#    ones are paused. Paused monitors that fit again resume and are checked
#    at once.
#
# Both steps are set-based: one UPDATE per distinct disallowed interval, and
# two UPDATEs for the count however many apps and monitors there are.
# Self-hosted, every monitor runs and intervals are left unchanged.
module Account::UptimeMonitoring
  extend ActiveSupport::Concern

  # Each monitor's place in its app, oldest first (1, 2, …).
  APP_RANK_SQL = "ROW_NUMBER() OVER (PARTITION BY uptime_monitors.project_id ORDER BY uptime_monitors.id) AS app_rank".freeze

  included do
    has_many :uptime_monitors, through: :projects
  end

  def fit_uptime_monitors_to_entitlements(now: Time.current)
    allowed = entitlements
    fit_uptime_intervals(allowed, now)
    fit_monitor_count(allowed.max_monitors, now)
  end

  private
    def account_monitors = UptimeMonitor.where(project_id: projects.select(:id))

    def fit_uptime_intervals(allowed, now)
      return if allowed.unlimited?

      outside = account_monitors.where.not(interval_minutes: allowed.uptime_intervals).distinct.pluck(:interval_minutes)
      outside.each do |minutes|
        account_monitors.where(interval_minutes: minutes)
          .update_all(interval_minutes: allowed.nearest_uptime_interval(minutes), updated_at: now)
      end
    end

    def fit_monitor_count(max_monitors, now)
      over = max_monitors && monitors_over_app_limit(max_monitors)
      fitting = over ? account_monitors.where.not(id: over) : account_monitors
      fitting.where.not(paused_at: nil).update_all(paused_at: nil, next_check_at: now, updated_at: now)
      account_monitors.where(id: over, paused_at: nil).update_all(paused_at: now, updated_at: now) if over
    end

    # A subquery of the ids beyond the oldest max_monitors of each app.
    def monitors_over_app_limit(max_monitors)
      ranked = account_monitors.select(:id, APP_RANK_SQL)
      UptimeMonitor.unscoped.from(ranked, :ranked).where("ranked.app_rank > ?", max_monitors).select("ranked.id")
    end
end
