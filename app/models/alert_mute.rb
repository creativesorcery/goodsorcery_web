# The one-click "mute" link in alert emails (List-Unsubscribe): turns off one
# app's instant alerts, its uptime alerts or its daily digest, for one person
# without signing in. The token is signed (not encrypted) and carries ids only; it expires,
# and stops working once the person leaves the app's account.
#
#   token = AlertMute.token_for(user, project)                 # alerts
#   token = AlertMute.token_for(user, project, stream: "digest")   # or "uptime"
#   AlertMute.find_by_token(token)&.apply
class AlertMute
  EXPIRES_IN = 60.days
  PURPOSE = :alert_mute

  attr_reader :membership, :project, :stream

  def self.token_for(user, project, stream: "alerts")
    raise ArgumentError, "unknown stream" unless NotificationPreference::STREAMS.include?(stream.to_s)

    payload = { "user_id" => user.id, "project_id" => project.id, "stream" => stream.to_s }
    verifier.generate(payload, purpose: PURPOSE, expires_in: EXPIRES_IN)
  end

  # The mute a valid token stands for, or nil (tampered, expired, unknown
  # stream, deleted app, or the person is no longer a member).
  def self.find_by_token(token)
    payload = verifier.verified(token.to_s, purpose: PURPOSE)
    from_payload(payload) if payload.is_a?(Hash)
  end

  def self.from_payload(payload)
    return unless NotificationPreference::STREAMS.include?(payload["stream"])

    project = Project.includes(:account).find_by(id: payload["project_id"])
    membership = project&.account&.memberships&.includes(:user)&.find_by(user_id: payload["user_id"])
    new(membership:, project:, stream: payload["stream"]) if membership
  end
  private_class_method :from_payload

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end

  def initialize(membership:, project:, stream:)
    @membership, @project, @stream = membership, project, stream
  end

  def user = membership.user

  def digest? = stream == "digest"

  def uptime? = stream == "uptime"

  # Already off: the link was used before, or the person switched it off.
  def applied?
    !membership.notification_preference_for(project).receives?(stream)
  end

  def apply
    membership.update_notification_preference(project, **NotificationPreference.stopped_attributes(stream))
  end
end
