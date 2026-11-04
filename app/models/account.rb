class Account < ApplicationRecord
  has_many :memberships, dependent: :delete_all, inverse_of: :account
  has_many :users, through: :memberships
  has_many :projects, inverse_of: :account # rows cascade in the database

  validates :name, presence: true, length: { maximum: 80 }
  validates :monthly_event_quota, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :entitlement_values_well_formed, if: :entitlement_values_changed?

  def entitlements
    Entitlements.new(entitlement_values, account_id: id)
  end

  # Replaces the whole stored document; the single write path for pushed
  # values (docs/ARCHITECTURE.md §12.3). Unknown keys are dropped.
  def update_entitlements!(values)
    values = values.to_hash.stringify_keys
    log_unknown_entitlement_keys(values.keys - Entitlements::KEYS)
    update!(entitlement_values: values.slice(*Entitlements::KEYS))
  end

  def accessible_by?(user)
    user.present? && memberships.exists?(user_id: user.id)
  end

  def member?(user) = accessible_by?(user)

  # Cached for five minutes; only a number is stored.
  def events_this_month
    month = Time.current.utc.beginning_of_month
    Rails.cache.fetch([ self, :events_this_month, month.strftime("%Y-%m") ], expires_in: 5.minutes) do
      ProjectHourlyCount.where(project_id: projects.select(:id), hour: month..).sum(:count)
    end
  end

  # Ingest's quota gate, cached for a minute; only a boolean is stored.
  def self.over_quota?(id)
    Rails.cache.fetch([ "account_over_quota", id ], expires_in: 1.minute) { find_by(id:)&.over_quota? || false }
  end

  def over_quota?
    monthly_event_quota.present? && events_this_month >= monthly_event_quota
  end

  # 0..1, or nil when the account has no quota (self-hosted).
  def event_quota_fraction
    return if monthly_event_quota.nil?

    [ events_this_month.fdiv(monthly_event_quota), 1.0 ].min
  end

  private
    def entitlement_values_well_formed
      Entitlements.problems(entitlement_values).each { |problem| errors.add(:base, problem) }
    end

    # Key names only, never values; capped and inspected so they can't forge log lines.
    def log_unknown_entitlement_keys(keys)
      return if keys.empty?

      names = keys.first(10).map { |key| key.truncate(40).inspect }.join(", ")
      Rails.logger.info("Dropping unknown entitlement keys #{names} for account #{id}")
    end
end
