# A signed-in browser. Sessions end after ABSOLUTE_LIFETIME, or after
# IDLE_TIMEOUT without a request; activity is recorded at most hourly.
class Session < ApplicationRecord
  ABSOLUTE_LIFETIME = 30.days
  IDLE_TIMEOUT = 7.days
  ACTIVITY_GRANULARITY = 1.hour

  belongs_to :user
  belongs_to :account

  scope :active, -> { where(created_at: ABSOLUTE_LIFETIME.ago.., updated_at: IDLE_TIMEOUT.ago..) }

  def expires_at = created_at + ABSOLUTE_LIFETIME

  # One UPDATE per hour at most, without callbacks or validations.
  def record_activity
    update_column(:updated_at, Time.current) if updated_at < ACTIVITY_GRANULARITY.ago
  end
end
