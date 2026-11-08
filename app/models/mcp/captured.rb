# Bounds captured values (already scrubbed and redacted at ingest) before
# they go into a tool result: strings are cut, hashes and arrays keep their
# first entries, nesting stops at MAX_DEPTH, and the whole value spends a byte
# budget (Mcp::OutputBudget, SECTION_BYTES unless the caller passes a shared
# one), so even an event at the ingest size limit gives a small result.
# Never logs or caches anything.
#
#   Mcp::Captured.trim({ "params" => { … } })
#   Mcp::Captured.trim(occurrence.params, budget: budget.section(2_500))
#   Mcp::Captured.string(message, 500)
module Mcp::Captured
  MAX_STRING = 300
  MAX_KEY = 64
  MAX_KEYS = 30
  MAX_ITEMS = 10
  MAX_DEPTH = 3
  SECTION_BYTES = 4_000
  CUT = "…".freeze

  module_function

  def trim(value, budget: Mcp::OutputBudget.new(SECTION_BYTES), depth: 0)
    case value
    when Hash then trim_hash(value, budget, depth)
    when Array then trim_array(value, budget, depth)
    when String then budget.string(value, MAX_STRING)
    else value.tap { budget.spend(value.to_json.bytesize) }
    end
  end

  def string(value, limit = MAX_STRING)
    text = value.to_s
    text.length > limit ? "#{text[0, limit]}#{CUT}" : text
  end

  # Entries are taken one by one while the budget lasts.
  def trim_hash(hash, budget, depth)
    return "{…}" if depth >= MAX_DEPTH && hash.any?

    trimmed = hash.lazy.take(MAX_KEYS).take_while { budget.available? }
      .to_h { |key, value| [ budget.string(key, MAX_KEY), trim(value, budget:, depth: depth + 1) ] }
    trimmed[CUT] = "#{hash.size - trimmed.size} more keys" if trimmed.size < hash.size
    trimmed
  end

  def trim_array(array, budget, depth)
    return "[…]" if depth >= MAX_DEPTH && array.any?

    trimmed = array.lazy.take(MAX_ITEMS).take_while { budget.available? }.map { |value| trim(value, budget:, depth: depth + 1) }.to_a
    trimmed << "#{array.size - trimmed.size} more items" if trimmed.size < array.size
    trimmed
  end
end
