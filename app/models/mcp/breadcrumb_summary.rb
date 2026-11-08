# An occurrence's breadcrumbs for a tool result: the last MAX_CRUMBS before
# the error, oldest first, each bounded (Mcp::Captured).
class Mcp::BreadcrumbSummary
  MAX_CRUMBS = 25

  def initialize(breadcrumbs)
    @breadcrumbs = Array(breadcrumbs).grep(Hash)
  end

  def crumbs
    @crumbs ||= @breadcrumbs.last(MAX_CRUMBS).map do |crumb|
      { offset_ms: crumb["offset_ms"], category: crumb["category"].presence || "custom", level: crumb["level"],
        message: Mcp::Captured.string(crumb["message"]), data: Mcp::Captured.trim(crumb["data"].presence) }.compact
    end
  end

  def total = @breadcrumbs.size

  def text_lines
    crumbs.map do |crumb|
      data = crumb[:data].is_a?(Hash) ? " #{crumb[:data].to_json}" : ""
      "#{crumb[:offset_ms].to_i.to_s.rjust(7)}ms [#{crumb[:category]}#{"/#{crumb[:level]}" if crumb[:level]}] #{crumb[:message]}#{data}"
    end
  end
end
