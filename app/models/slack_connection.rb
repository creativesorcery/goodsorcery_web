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

  encrypts :webhook_url

  normalizes :webhook_url, with: ->(url) { url.strip }

  scope :enabled, -> { where(enabled: true) }

  validates :project_id, uniqueness: true
  validate :webhook_url_from_slack

  # A new URL is a fresh start, and switching back on clears the rejection.
  before_save :reconnect, if: -> { webhook_url_changed? || (enabled_changed? && enabled?) }

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

  # Turns the connection off because Slack rejected the webhook, recording when
  # and Slack's reason. Returns true only for the call that turned it off (one
  # atomic UPDATE), so the owners are emailed once however many posts fail.
  def turn_off_after_rejection(reason, at: Time.current)
    turned_off = self.class.where(id:, disabled_at: nil).update_all(enabled: false, disabled_at: at, disabled_reason: reason, updated_at: at) == 1
    reload
    notify_owners_of_rejection if turned_off
    turned_off
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

    def notify_owners_of_rejection
      owners_to_notify.each { |user| AlertsMailer.slack_disabled(user, project).deliver_later }
    end

    def reconnect
      self.enabled = true
      self.disabled_at = nil
      self.disabled_reason = nil
    end
end
