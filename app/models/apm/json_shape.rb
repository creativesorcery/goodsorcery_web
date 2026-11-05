# Type checks for the performance payloads' JSON values, shared by the
# envelopes (request-time validation) and the payload readers. JSON numbers
# parse to Integer or Float; NaN and Infinity never parse.
module Apm::JsonShape
  module_function

  def integer?(value, min: nil, max: nil)
    value.is_a?(Integer) && (min.nil? || value >= min) && (max.nil? || value <= max)
  end

  def number?(value, min: 0) = value.is_a?(Numeric) && value.finite? && value >= min

  def optional_number?(value) = value.nil? || number?(value)

  def optional_string?(value) = value.nil? || value.is_a?(String)

  def list?(value, sizes) = value.is_a?(Array) && sizes.cover?(value.size)

  # A UTC time from an ISO 8601 string, or nil.
  def time(value)
    return unless value.is_a?(String) && value.match?(/\A\d{4}-\d\d-\d\dT/)

    Time.iso8601(value).utc
  rescue ArgumentError
    nil
  end

  # The time when it is the exact start of a minute, else nil.
  def minute(value)
    at = time(value)
    at if at && at.sec.zero? && at.subsec.zero?
  end

  # A string cut to max characters, or nil for anything that is not a string.
  def text(value, max) = value.is_a?(String) ? value.first(max) : nil
end
