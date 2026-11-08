# An app's Slack channel: one incoming-webhook URL that alerts are posted to
# (docs/ARCHITECTURE.md §11.5). The same rules and environment scope as
# email decide what is posted (SlackIssueAlert, SlackUptimeAlert).
#
# The webhook URL is the credential: anyone holding it can post to the
# channel. It is encrypted, accepted only in the exact shape Slack issues
# (https://hooks.slack.com/services/T…/B…/secret, nothing else), and shown
# only masked (#masked_webhook_url) on Settings › Alerts. It never goes into
# job arguments, logs, the cache, broadcasts, validation or exception
# messages, or slack_deliveries.
#
#   connection.status                       # => "connected", "off" or "rejected"
#   connection.paste_webhook_url(url, by: Current.user)   # => true, or false with errors
#   connection.turn_off_after_rejection("channel_not_found")
#   connection.claim_test_message           # => true at most once per TEST_MESSAGE_GAP
class SlackConnection < ApplicationRecord
  WEBHOOK_URL = %r{\Ahttps://hooks\.slack\.com/services/T[A-Z0-9]{2,20}/B[A-Z0-9]{2,20}/[A-Za-z0-9]{8,64}\z}
  URL_MESSAGE = "must be a Slack incoming webhook URL, starting https://hooks.slack.com/services/".freeze
  TEST_MESSAGE_GAP = 30.seconds
  DOCS_URL = "https://api.slack.com/messaging/webhooks".freeze
  REASON_LABELS = {
    "invalid_token" => "the webhook was revoked",
    "action_prohibited" => "posting was blocked by a workspace admin",
    "channel_not_found" => "the channel no longer exists",
    "channel_is_archived" => "the channel is archived",
    "no_service" => "the webhook was removed or its app uninstalled",
    "no_team" => "the workspace no longer exists",
    "team_not_found" => "the workspace no longer exists",
    "invalid_team" => "the workspace no longer exists",
    "team_disabled" => "the workspace was disabled",
    "http_404" => "the webhook no longer exists",
    "http_410" => "the webhook no longer exists"
  }.freeze

  belongs_to :project, inverse_of: :slack_connection
  belongs_to :connected_by, class_name: "User", foreign_key: :connected_by_user_id, optional: true

  encrypts :webhook_url

  normalizes :webhook_url, with: ->(url) { url.strip }

  scope :enabled, -> { where(enabled: true) }

  validates :project_id, uniqueness: true
  validate :webhook_url_from_slack

  # A pasted URL (a new one, or the saved one again) is a fresh start, and
  # switching back on clears the rejection. connected_at marks which URL a
  # rejection belongs to (#turn_off_after_rejection).
  before_save :stamp_connected_at, if: :webhook_url_changed?
  before_save :reconnect, if: -> { connected_at_changed? || (enabled_changed? && enabled?) }

  # Slack turned the webhook down (and so did we): disabled_at and the reason are kept.
  def rejected? = !enabled? && disabled_at.present?

  def status
    return "connected" if enabled?

    rejected? ? "rejected" : "off"
  end

  # Why Slack turned the webhook down, in words ("the channel is archived").
  def rejection_label = REASON_LABELS.fetch(disabled_reason.to_s, "Slack refused it")

  # "https://hooks.slack.com/services/T0A1…/B0B2…/••••••••": enough to recognise it, never the secret.
  # From the saved URL, so a rejected replacement never shows.
  def masked_webhook_url
    team, bot = attribute_in_database(:webhook_url).to_s.split("/").values_at(4, 5)
    "https://hooks.slack.com/services/#{team.to_s.first(4)}…/#{bot.to_s.first(4)}…/••••••••"
  end

  # Saves a pasted URL, the saved one again included: switched on, any
  # rejection cleared, and who pasted it and when recorded. On a validation
  # error nothing else changes (the page shows the saved state and the error).
  def paste_webhook_url(url, by:)
    assign_attributes(webhook_url: url, enabled: true, connected_by: by, connected_at: Time.current)
    return true if save

    restore_attributes(%i[enabled connected_by_user_id connected_at])
    false
  end

  # Turns the connection off because Slack rejected the webhook, recording when
  # and Slack's reason. Returns true only for the call that turned it off (one
  # atomic UPDATE), so a rejection is acted on once however many posts fail.
  #
  # Applies only while the URL this record was loaded with is still the saved
  # one (connected_at unchanged): a post to a URL that was replaced or pasted
  # again meanwhile can't turn off the replacement. A deleted connection
  # changes nothing. Owners are emailed at most once a day per app
  # (#notify_owners_of_rejection), however often a rejection is cleared.
  def turn_off_after_rejection(reason, at: Time.current)
    turned_off = self.class.where(id:, disabled_at: nil, connected_at:)
      .update_all(enabled: false, disabled_at: at, disabled_reason: reason, updated_at: at) == 1
    return false unless turned_off

    assign_attributes(enabled: false, disabled_at: at, disabled_reason: reason, updated_at: at)
    clear_attribute_changes(%i[enabled disabled_at disabled_reason updated_at])
    notify_owners_of_rejection(at)
    true
  end

  # One test message per TEST_MESSAGE_GAP per connection, whoever asks
  # (atomic, so double clicks and two members can't both send one).
  def claim_test_message(now: Time.current)
    claimed = self.class.where(id:).where("test_sent_at IS NULL OR test_sent_at <= ?", now - TEST_MESSAGE_GAP)
      .update_all(test_sent_at: now) == 1
    self.test_sent_at = now if claimed
    claimed
  end

  # The owners told when Slack rejects the webhook (verified addresses only).
  def owners_to_notify
    User.where(id: project.account.memberships.owner.with_verified_email.select(:user_id))
  end

  private
    # The message never echoes the value.
    def webhook_url_from_slack
      return errors.add(:webhook_url, :blank) if webhook_url.blank?

      errors.add(:webhook_url, URL_MESSAGE) unless WEBHOOK_URL.match?(webhook_url)
    end

    # Throttled per owner and app through alert_deliveries (one key per UTC
    # day), so neither switching back on nor disconnecting and reconnecting
    # can make a rejection email the owners again the same day.
    def notify_owners_of_rejection(at)
      dedupe_key = AlertDelivery.slack_disabled_key(project, at)
      owners_to_notify.each do |user|
        next unless AlertDelivery.record(user:, project:, kind: :slack_disabled, dedupe_key:)

        AlertsMailer.slack_disabled(user, project).deliver_later
      end
    end

    def stamp_connected_at
      self.connected_at = Time.current unless connected_at_changed?
    end

    def reconnect
      self.enabled = true
      self.disabled_at = nil
      self.disabled_reason = nil
    end
end
