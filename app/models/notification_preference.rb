# One member's choices for one app's alert emails. Rows are sparse: without
# one, a member gets the app's instant alerts and its daily digest (when the
# app's digest rule is on). Use Membership#notification_preference_for, which
# falls back to an unsaved default.
class NotificationPreference < ApplicationRecord
  # The two kinds of email a member can turn off, one switch each.
  STREAMS = %w[alerts digest].freeze
  STOPPED = { "alerts" => { alerts_muted: true }, "digest" => { digest_enabled: false } }.freeze

  belongs_to :membership, inverse_of: :notification_preferences
  belongs_to :project, inverse_of: :notification_preferences

  validates :project_id, uniqueness: { scope: :membership_id }
  validate :project_in_membership_account

  # The attributes that turn a stream off ("alerts" or "digest").
  def self.stopped_attributes(stream)
    STOPPED.fetch(stream.to_s)
  end

  def receives?(stream)
    stream.to_s == "digest" ? digest_enabled? : !alerts_muted?
  end

  private
    def project_in_membership_account
      return if membership.nil? || project.nil? || membership.account_id == project.account_id

      errors.add(:project, "must belong to the member's account")
    end
end
