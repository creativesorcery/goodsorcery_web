class Membership < ApplicationRecord
  belongs_to :account, inverse_of: :memberships
  belongs_to :user, inverse_of: :memberships
  has_many :notification_preferences, inverse_of: :membership # rows cascade in the database

  enum :role, { owner: "owner", member: "member" }, validate: true

  validates :user_id, uniqueness: { scope: :account_id }

  scope :with_verified_email, -> { joins(:user).merge(User.email_verified) }
  scope :receiving_alerts_for, ->(project) do
    with_verified_email.where.not(id: NotificationPreference.where(project:, alerts_muted: true).select(:membership_id))
  end
  scope :receiving_uptime_alerts_for, ->(project) do
    with_verified_email.where.not(id: NotificationPreference.where(project:, uptime_alerts_muted: true).select(:membership_id))
  end
  scope :receiving_digest_for, ->(project) do
    with_verified_email.where.not(id: NotificationPreference.where(project:, digest_enabled: false).select(:membership_id))
  end

  # Losing access must also end any browser session working in that account.
  after_destroy_commit :end_sessions

  # Never mails an unconfirmed address. Checked again at send time.
  def receives_alerts?(project)
    user.email_verified? && notification_preference_for(project).receives?("alerts")
  end

  def receives_uptime_alerts?(project)
    user.email_verified? && notification_preference_for(project).receives?("uptime")
  end

  def receives_digest?(project)
    user.email_verified? && notification_preference_for(project).receives?("digest")
  end

  # The saved choices for that app (from loaded preferences when present),
  # or an unsaved default: alerts, uptime alerts and digest on.
  def notification_preference_for(project)
    notification_preferences.find { |preference| preference.project_id == project.id } ||
      NotificationPreference.new(membership_id: id, project_id: project.id)
  end

  # Saves the switches for that app, creating the row the first time. A
  # concurrent first save loses on the unique index and retries as an update.
  def update_notification_preference(project, **attributes)
    notification_preferences.find_or_initialize_by(project:).update!(attributes)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  private
    def end_sessions
      Session.where(user_id:, account_id:).delete_all
    end
end
