# Lenient ISO 8601 parsing for client-supplied times.
module Ingest::Timestamp
  def self.parse(value)
    Time.iso8601(value).in_time_zone("UTC") if value.is_a?(String)
  rescue ArgumentError
    nil
  end

  # The client's time when within [received_at - 30 days, received_at + 5 minutes],
  # otherwise the receive time.
  def self.clamp(time, received_at:)
    window = (received_at - 30.days)..(received_at + 5.minutes)
    time && window.cover?(time) ? time : received_at
  end
end
