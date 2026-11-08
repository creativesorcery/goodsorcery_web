# Small formatting helpers for the plain-text half of tool results (the
# other half is structuredContent). Times are ISO 8601 in UTC.
module Mcp::Text
  module_function

  # A user-supplied value echoed back in a message: quoted, short, one line.
  def quote(value) = "\"#{value.to_s.squish.truncate(60)}\""

  def time(value) = value&.utc&.iso8601

  # "1,284"
  def count(number) = ActiveSupport::NumberHelper.number_to_delimited(number.to_i)

  # "412.7ms", or "–" for no value.
  def ms(value) = value.nil? ? "–" : "#{value.to_f.round(1)}ms"

  # "12.5%" of a 0..1 fraction (or of a 0..100 percentage with percent: true).
  def percent(value, percent: false)
    return "–" if value.nil?

    "#{(percent ? value.to_f : value.to_f * 100).round(2)}%"
  end

  def lines(*parts) = parts.flatten.compact.join("\n")
end
