# One stored uptime check result (the immediate retry folded in). Rows hold
# the outcome only: no URL, body, headers or exception message. Kept at most
# MAX_KEPT_DAYS (Ingest::Retention#prune_uptime); percentages and status bars
# read UptimeHourlyCount instead.
class UptimeCheck < ApplicationRecord
  ERROR_KINDS = %w[timeout dns_failure connection_refused tls_error http_status blocked_address connection_error].freeze
  ERROR_LABELS = {
    "timeout" => "Timed out after #{UptimeProbe::TOTAL_TIMEOUT} s",
    "dns_failure" => "DNS lookup failed",
    "connection_refused" => "Connection refused",
    "tls_error" => "TLS handshake failed",
    "blocked_address" => "Address not allowed",
    "connection_error" => "Connection failed"
  }.freeze
  MAX_KEPT_DAYS = 7
  RESPONSE_BUCKET = 15.minutes

  belongs_to :uptime_monitor, inverse_of: :checks

  enum :status, { up: "up", down: "down" }, validate: true
  validates :error_kind, inclusion: { in: ERROR_KINDS }, allow_nil: true

  scope :recent, -> { order(checked_at: :desc) }

  # Shared by the UI and the alert emails; nil when there was no error.
  def self.error_label(kind, http_status = nil)
    return if kind.blank?
    return "HTTP #{http_status}" if kind.to_s == "http_status" && http_status

    ERROR_LABELS.fetch(kind.to_s, ERROR_LABELS["connection_error"])
  end

  # [[bucket_start, average ms], ...] of up checks in 15-minute buckets, oldest
  # first, only buckets with data (at most 96 for 24 hours). One query.
  def self.response_series(monitor, since: 24.hours.ago)
    bucket = Arel.sql(format("date_bin('%d seconds', checked_at, TIMESTAMP '1970-01-01')", RESPONSE_BUCKET.to_i))
    up.where(uptime_monitor: monitor, checked_at: since..).where.not(response_time_ms: nil)
      .group(bucket).order(bucket).average(:response_time_ms)
      .map { |time, average| [ time, average.round ] }
  end

  def error_label = self.class.error_label(error_kind, http_status)
end
