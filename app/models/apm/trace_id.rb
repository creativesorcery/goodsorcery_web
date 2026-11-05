# Trace ids are UUIDv7 (docs/ARCHITECTURE.md §13.0): the first 48 bits are
# the start time in Unix milliseconds, which Apm::TraceLookup reads to tell
# an expired trace from an unknown id.
module Apm::TraceId
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  V7 = /\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/i

  module_function

  # The id downcased when it is a UUID string, else nil.
  def uuid(value)
    value.downcase if value.is_a?(String) && value.match?(UUID)
  end

  def v7?(value) = value.is_a?(String) && value.match?(V7)

  # The embedded time of a UUIDv7, or nil for anything else.
  def time(value)
    Time.zone.at(Rational(value.delete("-").first(12).to_i(16), 1000)) if v7?(value)
  end

  # A UUIDv7 for a given time (seeds and generated ids).
  def generate(at = Time.current)
    hex = format("%012x", (at.to_r * 1000).floor) + "7" + SecureRandom.hex(2)[1, 3] +
          %w[8 9 a b].sample + SecureRandom.hex(8)[1, 15]
    [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
  end
end
