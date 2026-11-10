class Account < ApplicationRecord
  # Replaced by the monthly_event_quota entitlement (docs/ARCHITECTURE.md
  # §12.2.2). Kept in the table for one release so the previous one still
  # runs during a deploy and after a rollback; a later release drops it.
  self.ignored_columns += [ "monthly_event_quota" ]

  has_many :memberships, dependent: :delete_all, inverse_of: :account
  has_many :users, through: :memberships
  has_many :projects, inverse_of: :account # rows cascade in the database

  # After has_many :projects, which its has_many :through needs.
  include Account::UptimeMonitoring, Account::ProjectRetention, Account::EventQuota
  include StaffSearchable

  staff_searchable_by :name

  # Each account's member count in the same query as the accounts (the staff list).
  scope :with_users_count, -> {
    select(arel_table[Arel.star], "(SELECT COUNT(*) FROM memberships WHERE memberships.account_id = accounts.id) AS users_count")
  }

  validates :name, presence: true, length: { maximum: 80 }
  validate :entitlement_values_well_formed, if: :entitlement_values_changed?

  after_update_commit :fit_to_entitlements, if: :saved_change_to_entitlement_values?

  def entitlements
    Entitlements.new(entitlement_values, account_id: id)
  end

  # Brings monitors and app retention within the entitlements
  # (docs/ARCHITECTURE.md §12.3.1-12.3.2): after a commit that changes
  # entitlement_values, and from bin/rails goodsorcery:fit_entitlements after
  # hosted mode or config/entitlements.yml changes.
  def fit_to_entitlements(now: Time.current)
    fit_uptime_monitors_to_entitlements(now:)
    fit_project_retention_to_entitlements(now:)
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
