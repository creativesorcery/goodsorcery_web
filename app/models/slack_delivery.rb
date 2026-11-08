# One Slack post decided for one app: the throttle, the hourly cap and the
# audit log of Slack alerts (docs/ARCHITECTURE.md §11.5). The Slack
# counterpart of AlertDelivery, keyed per app instead of per user, since a
# channel gets one post per event however many members the app has.
#
# Rows hold ids, the kind, a dedupe key and (summaries) counts per kind, never
# captured data or the webhook URL. Keys are AlertDelivery's own with a
# "slack:" prefix, so an alert is posted at most once per issue transition,
# still_happening window, incident or summary hour; the unique
# [project_id, dedupe_key] index makes that race-safe across retries, sweeps
# and concurrent jobs.
#
#   SlackDelivery.claim(project:, kind: "new_issue", issue:)    # => record, folded record or nil
#   SlackDelivery.record(project:, kind: "monitor_down", uptime_incident: incident)
#
# Issue alerts over HOURLY_CAP in one app are recorded `folded`; SlackSummary
# posts one "and N more alerts" message for them after the hour. Uptime
# alerts and summaries are never folded and don't count, as with email.
class SlackDelivery < ApplicationRecord
  KINDS = [ *(AlertRule::KINDS - %w[daily_digest]), "summary" ].freeze
  # Issue-alert posts per app per hour before the rest are folded into a summary.
  HOURLY_CAP = 30
  KEY_PREFIX = "slack:".freeze
  # Namespace of the per-app advisory lock that makes the cap race-safe.
  CAP_LOCK = 4_712

  belongs_to :project
  belongs_to :issue, optional: true
  belongs_to :uptime_incident, optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :status, { sent: "sent", folded: "folded" }, validate: true

  scope :since, ->(time) { where(created_at: time..) }
  scope :awaiting_summary, -> { folded.where(summarized_at: nil) }

  class << self
    # Inserts the delivery unless the app already has one with this key.
    # Returns the new row, or nil for a duplicate. Skips validations: pass a
    # kind from KINDS. created_at is the app clock (`at`), which the cap and
    # throttle windows are measured against.
    def record(project:, kind:, issue: nil, uptime_incident: nil, status: "sent", summary_counts: nil, at: Time.current)
      row = { project_id: project.id, issue_id: issue&.id, uptime_incident_id: uptime_incident&.id, kind: kind.to_s, status: status.to_s,
              dedupe_key: dedupe_key(kind, issue || uptime_incident, at:), summary_counts:, created_at: at }
      id = insert(row, unique_by: %i[project_id dedupe_key], returning: %i[id]).rows.first&.first
      find(id) if id
    end

    # An issue alert: "sent" under the app's hourly cap, "folded" at it.
    # Returns the row (check #sent?), or nil when the key was already used.
    # Count and insert run under a per-app lock; uncached since jobs run with
    # the query cache on.
    def claim(project:, kind:, issue:)
      uncached do
        transaction do
          lock_cap(project)
          record(project:, kind:, issue:, status: cap_reached?(project) ? "folded" : "sent")
        end
      end
    end

    # "slack:new_issue:12", "slack:regression:12:<epoch>", "slack:still_happening:12:<window>",
    # "slack:monitor_down:<incident>", "slack:summary:<hour>".
    def dedupe_key(kind, subject, at: Time.current)
      key = case kind.to_s
      when "summary" then AlertDelivery.summary_key(at)
      when *AlertRule::UPTIME_KINDS then AlertDelivery.incident_key(kind, subject)
      else AlertDelivery.issue_key(kind, subject, at:)
      end
      "#{KEY_PREFIX}#{key}"
    end

    def sent_in_last_hour(project)
      where(project:, kind: AlertRule::INSTANT_KINDS).sent.since(1.hour.ago).count
    end

    def cap_reached?(project) = sent_in_last_hour(project) >= HOURLY_CAP

    # Was this issue posted (or folded) for this kind within the window?
    def posted_recently?(issue, kind, within: AlertDelivery::STILL_HAPPENING_WINDOW)
      where(issue:, kind: kind.to_s).since(within.ago).exists?
    end

    private
      def lock_cap(project)
        connection.execute(sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?, hashint8(?))", CAP_LOCK, project.id ]))
      end
  end

  def summary? = kind == "summary"

  def posted? = posted_at.present?

  # Marks the post done; false if another run already did.
  def mark_posted(at: Time.current)
    self.class.where(id:, posted_at: nil).update_all(posted_at: at) == 1
  end
end
