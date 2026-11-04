# An account's uptime monitors and keeping them within its entitlements
# (docs/ARCHITECTURE.md §12.3.1). Entitlements are account-level, so the
# monitor limit counts the monitors of every app in the account.
#
# Fitting runs after a commit that changes entitlement_values, after a monitor
# is destroyed, and from bin/rails goodsorcery:fit_uptime_monitors:
#
# 1. A monitor whose interval isn't allowed moves to the nearest allowed one.
# 2. The oldest monitors (by id) up to max_monitors run; newer ones are paused.
#    Paused monitors that fit again resume and are checked at once.
#
# Self-hosted, every monitor runs and intervals are left unchanged.
module Account::UptimeMonitoring
  extend ActiveSupport::Concern

  included do
    has_many :uptime_monitors, through: :projects

    after_update_commit :fit_uptime_monitors_to_entitlements, if: :saved_change_to_entitlement_values?
  end

  def monitor_limit_reached? = entitlements.monitor_limit_reached?(uptime_monitors.count)

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
      over = max_monitors && account_monitors.order(:id).offset(max_monitors).select(:id)
      fitting = over ? account_monitors.where.not(id: over) : account_monitors
      fitting.where.not(paused_at: nil).update_all(paused_at: nil, next_check_at: now, updated_at: now)
      account_monitors.where(id: over, paused_at: nil).update_all(paused_at: now, updated_at: now) if over
    end
end
