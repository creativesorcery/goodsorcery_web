# One alert email decided for one recipient: the throttle and audit log.
# Rows hold ids, the rule kind and a dedupe key, never captured data.
#
# Throttling is race-safe through the unique [user_id, dedupe_key] index:
# .record inserts with ON CONFLICT DO NOTHING and returns nil when the key
# was already used, i.e. the email was already sent (or folded).
#
#   key = AlertDelivery.issue_key(:regression, issue)
#   AlertDelivery.record(user:, project:, kind: :regression, dedupe_key: key, issue:)
#   AlertDelivery.cap_reached?(user)   # HOURLY_CAP sent in the last hour
#
# Emails over the cap are recorded as `folded`; one summary email per user
# per hour ("and N more alerts") covers them and sets `summarized_at`.
class AlertDelivery < ApplicationRecord
  KINDS = [ *AlertRule::KINDS, "summary" ].freeze
  HOURLY_CAP = 20
  STILL_HAPPENING_WINDOW = 6.hours

  belongs_to :user
  belongs_to :project, inverse_of: :alert_deliveries
  belongs_to :issue, optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :status, { sent: "sent", folded: "folded" }, validate: true

  scope :since, ->(time) { where(created_at: time..) }
  scope :awaiting_summary, -> { folded.where(summarized_at: nil) }

  class << self
    # Inserts the delivery unless the user already has one with this key.
    # Returns the new id, or nil for a duplicate. Skips model validations:
    # pass a kind from KINDS and a status of "sent" or "folded".
    def record(user:, project:, kind:, dedupe_key:, issue: nil, status: "sent")
      row = { user_id: user.id, project_id: project.id, issue_id: issue&.id, kind: kind.to_s, dedupe_key:, status: status.to_s }
      insert(row, unique_by: %i[user_id dedupe_key], returning: %i[id]).rows.first&.first
    end

    # Once per transition: new_issue and reached_production happen once per
    # issue, a regression once per regressed_at; still_happening once per
    # six-hour window.
    def issue_key(kind, issue, at: Time.current)
      case kind.to_s
      when "regression" then "regression:#{issue.id}:#{issue.regressed_at.to_i}"
      when "still_happening" then "still_happening:#{issue.id}:#{at.to_i / STILL_HAPPENING_WINDOW.to_i}"
      else "#{kind}:#{issue.id}"
      end
    end

    # Once per user, app and local calendar day.
    def digest_key(project, local_date)
      "daily_digest:#{project.id}:#{local_date.iso8601}"
    end

    # One overflow summary per user per clock hour.
    def summary_key(at = Time.current)
      "summary:#{at.to_i / 1.hour.to_i}"
    end

    def sent_in_last_hour(user)
      where(user:).sent.since(1.hour.ago).count
    end

    def cap_reached?(user)
      sent_in_last_hour(user) >= HOURLY_CAP
    end

    # Any recipient alerted for this issue and rule within the window?
    def alerted_recently?(issue, kind, within: STILL_HAPPENING_WINDOW)
      where(issue:, kind: kind.to_s).since(within.ago).exists?
    end
  end
end
