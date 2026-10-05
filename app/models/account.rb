class Account < ApplicationRecord
  has_many :memberships, dependent: :delete_all, inverse_of: :account
  has_many :users, through: :memberships
  has_many :projects, inverse_of: :account # rows cascade in the database

  validates :name, presence: true, length: { maximum: 80 }
  validates :monthly_event_quota, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

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

  # 0..1, or nil when the account has no quota (self-hosted).
  def event_quota_fraction
    return if monthly_event_quota.nil?

    [ events_this_month.fdiv(monthly_event_quota), 1.0 ].min
  end
end
