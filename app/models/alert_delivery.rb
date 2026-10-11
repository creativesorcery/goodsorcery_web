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
#   AlertDelivery.claim(user:, project:, kind:, dedupe_key:, issue:)  # => "sent", "folded" or nil
#
# Instant alerts over the cap are recorded as `folded`; one summary email per
# user per hour ("and N more alerts", AlertSummary) covers them and sets
# `summarized_at`. Digests and summaries don't count towards the cap.
class AlertDelivery < ApplicationRecord
  KINDS = [ *AlertRule::KINDS, "summary" ].freeze
  HOURLY_CAP = 20
  STILL_HAPPENING_WINDOW = 6.hours
  # Every key's window is shorter, and new_issue/reached_production can't
  # happen twice for one issue, so older rows are pruned (Ingest::Retention).
  KEPT_FOR = 30.days
  # Namespace of the per-user advisory lock that makes the cap race-safe.
  CAP_LOCK = 4_711

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
    # pass a kind from KINDS and a status of "sent" or "folded". created_at is
    # the app clock, which the cap and throttle windows are measured against.
    def record(user:, project:, kind:, dedupe_key:, issue: nil, status: "sent")
      row = { user_id: user.id, project_id: project.id, issue_id: issue&.id, kind: kind.to_s, dedupe_key:, status: status.to_s,
              created_at: Time.current }
      insert(row, unique_by: %i[user_id dedupe_key], returning: %i[id]).rows.first&.first
    end

    # Records an instant alert for one recipient: "sent" while the user is
    # under the hourly cap, "folded" (for the summary) once it is reached.
    # Returns that status, or nil when the key was already used. The count
    # and the insert run under a per-user lock, so concurrent jobs can't push
    # a user past the cap. Uncached: jobs run with the query cache on.
    def claim(user:, **delivery)
      uncached do
        transaction do
          lock_cap(user)
          status = cap_reached?(user) ? "folded" : "sent"
          status if record(user:, **delivery, status:)
        end
      end
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

    # Instant alert emails only: digests and summaries are exempt.
    def sent_in_last_hour(user)
      where(user:, kind: AlertRule::INSTANT_KINDS).sent.since(1.hour.ago).count
    end

    def cap_reached?(user)
      sent_in_last_hour(user) >= HOURLY_CAP
    end

    # Any recipient alerted for this issue and rule within the window?
    def alerted_recently?(issue, kind, within: STILL_HAPPENING_WINDOW)
      where(issue:, kind: kind.to_s).since(within.ago).exists?
    end

    private
      # Transaction-scoped. hashint8 folds the bigint user id into the lock's
      # second int key; two users sharing a hash merely share a lock.
      def lock_cap(user)
        connection.execute(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?, hashint8(?))", CAP_LOCK, user.id ]))
      end
  end
end
