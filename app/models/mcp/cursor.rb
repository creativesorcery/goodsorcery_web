# Opaque pagination cursors for list tools: a small JSON object, base64url
# encoded. Clients pass back what they were given; anything else is an
# Mcp::InvalidArgument. A cursor holds a position only (an offset or an id),
# never captured data.
#
#   Mcp::Cursor.encode(offset: 20)       # => "eyJvZmZzZXQiOjIwfQ"
#   Mcp::Cursor.decode(cursor, :offset)  # => 20 (0 for a blank cursor)
module Mcp::Cursor
  MAX_VALUE = 1_000_000_000_000

  module_function

  def encode(**position) = Base64.urlsafe_encode64(position.to_json, padding: false)

  def decode(cursor, key)
    return 0 if cursor.blank?

    value = JSON.parse(Base64.urlsafe_decode64(cursor.to_s)).fetch(key.to_s)
    raise ArgumentError unless value.is_a?(Integer) && value.between?(0, MAX_VALUE)

    value
  rescue ArgumentError, JSON::ParserError, KeyError, TypeError, NoMethodError
    raise Mcp::InvalidArgument, "Invalid cursor. Pass the next_cursor of a previous result, or leave it out."
  end
end
