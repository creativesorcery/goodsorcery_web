# A signed-in browser. Sessions end after ABSOLUTE_LIFETIME, or after
# IDLE_TIMEOUT without a request; activity is recorded at most hourly.
class Session < ApplicationRecord
  ABSOLUTE_LIFETIME = 30.days
  IDLE_TIMEOUT = 7.days
  ACTIVITY_GRANULARITY = 1.hour

  belongs_to :user
  belongs_to :account

  scope :active, -> { where(created_at: ABSOLUTE_LIFETIME.ago.., updated_at: IDLE_TIMEOUT.ago..) }

  # Ends every session in this relation (a user's, or a user's in one
  # account) and closes their open live-update connections.
  def self.terminate_all
    includes(:user).find_each(&:terminate)
  end

  def expires_at = created_at + ABSOLUTE_LIFETIME

  # Signs this browser out and closes its open Action Cable connection.
  # Subscriptions are only authorised when they start, so without the
  # disconnect a socket opened earlier would keep receiving broadcasts.
  # The client reconnects at once, and the connection check then fails.
  def terminate
    destroy
    disconnect_live_updates
  end

  def disconnect_live_updates
    ActionCable.server.remote_connections.where(current_user: user, current_session: self).disconnect
  end

  # One UPDATE per hour at most, without callbacks or validations.
  def record_activity
    update_column(:updated_at, Time.current) if updated_at < ACTIVITY_GRANULARITY.ago
  end
end
