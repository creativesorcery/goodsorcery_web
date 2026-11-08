# An occurrence's breadcrumbs for a tool result: the last MAX_CRUMBS before
# the error, oldest first, each bounded (Mcp::Captured) and all of them
# within one byte budget. When the budget runs out the oldest are dropped.
class Mcp::BreadcrumbSummary
  MAX_CRUMBS = 25
  BYTES = 4_000
  DATA_BYTES = 500

  def initialize(breadcrumbs, budget: Mcp::OutputBudget.new(BYTES))
    @breadcrumbs = Array(breadcrumbs).grep(Hash)
    @budget = budget
  end

  # Taken newest first while the budget lasts, shown oldest first.
  def crumbs
    @crumbs ||= @breadcrumbs.last(MAX_CRUMBS).reverse.lazy.take_while { @budget.available? }.map { |crumb| present(crumb) }.to_a.reverse
  end

  def total = @breadcrumbs.size

  def text_lines
    earlier = total > crumbs.size ? [ "  … #{total - crumbs.size} earlier breadcrumbs" ] : []
    earlier + crumbs.map do |crumb|
      data = crumb[:data].is_a?(Hash) ? " #{crumb[:data].to_json}" : ""
      "#{crumb[:offset_ms].to_i.to_s.rjust(7)}ms [#{crumb[:category]}#{"/#{crumb[:level]}" if crumb[:level]}] #{crumb[:message]}#{data}"
    end
  end

  private
    def present(crumb)
      { offset_ms: crumb["offset_ms"], category: @budget.string(crumb["category"].presence || "custom", 64),
        level: (@budget.string(crumb["level"], 16) if crumb["level"]), message: @budget.string(crumb["message"], Mcp::Captured::MAX_STRING),
        data: (Mcp::Captured.trim(crumb["data"], budget: @budget.section(DATA_BYTES)) if crumb["data"].present?) }.compact
    end
end
