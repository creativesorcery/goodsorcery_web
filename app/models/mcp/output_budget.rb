# A byte allowance for the captured text in one part of a tool result, so a
# result stays small however large the stored event (ingest allows events of
# up to 512 KiB). Strings are measured as JSON, quotes and escapes included.
# A section draws from its own allowance and from its parent's, so a tool can
# cap each part (params, breadcrumbs, …) and the whole at once. Once it runs
# out, strings come back empty and collections stop (Mcp::Captured marks the
# cut with "N more").
#
#   budget = Mcp::OutputBudget.new(20_000)
#   params = Mcp::Captured.trim(occurrence.params, budget: budget.section(2_500))
#   budget.available?  # => true while bytes are left
class Mcp::OutputBudget
  def initialize(bytes, parent: nil)
    @remaining = bytes
    @parent = parent
  end

  def remaining = [ @remaining, @parent&.remaining ].compact.min

  def available? = remaining.positive?

  # A part of this allowance, capped at `bytes`.
  def section(bytes) = self.class.new(bytes, parent: self)

  # The string cut to `limit` characters and to what is left, which it spends.
  def string(value, limit)
    text = Mcp::Captured.string(value, remaining.clamp(0, limit))
    spend(text.to_json.bytesize)
    text
  end

  def spend(bytes)
    @remaining -= bytes
    @parent&.spend(bytes)
    nil
  end
end
