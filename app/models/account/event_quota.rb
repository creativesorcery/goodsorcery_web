# The monthly error event quota (docs/ARCHITECTURE.md §12.2.2): the
# monthly_event_quota entitlement, so nil (no quota) self-hosted and the
# stored value or the hosted default (config/entitlements.yml) hosted.
# Performance data never counts toward it.
#
# Ingest checks it on every request through Account.over_quota?(id), which
# costs nothing self-hosted and one cache read hosted: a boolean per account
# id, kept for OVER_QUOTA_TTL and rewritten after a commit that changes
# entitlement_values. A cache miss writes only when the key is still empty,
# so a miss that read the account just before such a commit can't put its
# stale answer over the fresh one. A change to the hosted defaults (which
# needs a restart) shows within OVER_QUOTA_TTL.
module Account::EventQuota
  extend ActiveSupport::Concern

  OVER_QUOTA_TTL = 1.minute
  EVENTS_THIS_MONTH_TTL = 5.minutes

  included do
    after_update_commit :refresh_over_quota, if: :saved_change_to_entitlement_values?
  end

  class_methods do
    # Ingest's quota gate; only a boolean is cached.
    def over_quota?(id)
      return false unless Rails.configuration.x.hosted

      cached = Rails.cache.read(over_quota_key(id))
      return cached unless cached.nil?

      remember_over_quota(id, find_by(id:)&.over_quota? || false, unless_exist: true)
    end

    # Returns the value. unless_exist: true leaves an answer already there.
    def remember_over_quota(id, value, unless_exist: false)
      Rails.cache.write(over_quota_key(id), value, expires_in: OVER_QUOTA_TTL, unless_exist:)
      value
    end

    def over_quota_key(id) = [ "account_over_quota", id ]
  end

  # Error events this UTC month, from the project rollups. Cached for five
  # minutes; only a number is stored.
  def events_this_month
    month = Time.current.utc.beginning_of_month
    Rails.cache.fetch([ self, :events_this_month, month.strftime("%Y-%m") ], expires_in: EVENTS_THIS_MONTH_TTL) do
      ProjectHourlyCount.where(project_id: projects.select(:id), hour: month..).sum(:count)
    end
  end

  def over_quota?
    quota = entitlements.monthly_event_quota
    !quota.nil? && events_this_month >= quota
  end

  # 0..1, or nil when the account has no quota (always so self-hosted).
  def event_quota_fraction
    quota = entitlements.monthly_event_quota
    return if quota.nil?

    [ events_this_month.fdiv(quota), 1.0 ].min
  end

  private
    # Self-hosted the key is never read; it is only cleared.
    def refresh_over_quota
      return Rails.cache.delete(self.class.over_quota_key(id)) unless Rails.configuration.x.hosted

      self.class.remember_over_quota(id, over_quota?)
    end
end
