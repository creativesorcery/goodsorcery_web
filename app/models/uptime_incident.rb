# One down period of a monitor, from the check that went down to the check
# that came back up; the dedupe unit for down/recovered alerts. The unique
# partial index index_uptime_incidents_one_open allows one open incident per
# monitor. Resolved incidents are kept for KEPT_FOR (Ingest::Retention).
class UptimeIncident < ApplicationRecord
  KEPT_FOR = 31.days

  belongs_to :uptime_monitor, inverse_of: :incidents

  scope :open, -> { where(resolved_at: nil) }
  scope :recent, -> { order(started_at: :desc) }

  def open? = resolved_at.nil?

  # Seconds, up to now while the incident is open.
  def duration(now: Time.current) = (resolved_at || now) - started_at

  def cause_label = UptimeCheck.error_label(error_kind, http_status)
end
