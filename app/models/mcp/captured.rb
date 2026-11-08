# Bounds captured values (already scrubbed and redacted at ingest) before
# they go into a tool result, so every response stays small (~50 KB at most):
# strings are cut, hashes and arrays keep their first entries and nesting
# stops at MAX_DEPTH. Never logs or caches anything.
#
#   Mcp::Captured.trim({ "params" => { … } })
#   Mcp::Captured.string(message, 500)
module Mcp::Captured
  MAX_STRING = 300
  MAX_KEYS = 30
  MAX_ITEMS = 10
  MAX_DEPTH = 3
  CUT = "…".freeze

  module_function

  def trim(value, depth: 0)
    case value
    when Hash then trim_hash(value, depth)
    when Array then trim_array(value, depth)
    when String then string(value)
    else value
    end
  end

  def string(value, limit = MAX_STRING)
    text = value.to_s
    text.length > limit ? "#{text[0, limit]}#{CUT}" : text
  end

  def trim_hash(hash, depth)
    return "{…}" if depth >= MAX_DEPTH && hash.any?

    trimmed = hash.first(MAX_KEYS).to_h { |key, value| [ string(key, 64), trim(value, depth: depth + 1) ] }
    trimmed[CUT] = "#{hash.size - MAX_KEYS} more keys" if hash.size > MAX_KEYS
    trimmed
  end

  def trim_array(array, depth)
    return "[…]" if depth >= MAX_DEPTH && array.any?

    trimmed = array.first(MAX_ITEMS).map { |value| trim(value, depth: depth + 1) }
    trimmed << "#{array.size - MAX_ITEMS} more items" if array.size > MAX_ITEMS
    trimmed
  end
end
