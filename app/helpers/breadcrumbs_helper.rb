# The issue page's breadcrumb timeline. Crumbs are decrypted occurrence data:
# escaped tags only (see CapturedDataHelper).
module BreadcrumbsHelper
  FILTERS = %w[sql http log].freeze
  TONES = {
    "sql" => { dot: "bg-lilac-400", chip: "text-lilac-300 border-lilac-400/30" },
    "http" => { dot: "bg-mint-400", chip: "text-mint-300 border-mint-400/30" },
    "log" => { dot: "bg-iris-400", chip: "text-iris-300 border-iris-400/30" }
  }.freeze
  DEFAULT_TONE = { dot: "bg-paper-500", chip: "" }.freeze
  LOUD_LEVELS = { "warning" => "[warn]", "error" => "[error]" }.freeze

  # -412 → "−412ms", -1204 → "−1,204ms"
  def breadcrumb_offset(offset_ms)
    milliseconds = offset_ms.to_i
    sign = milliseconds.negative? ? "−" : ""
    "#{sign}#{number_with_delimiter(milliseconds.abs)}ms"
  end

  def breadcrumb_tone(category)
    TONES.fetch(category.to_s, DEFAULT_TONE)
  end

  def breadcrumb_count(breadcrumbs, category)
    breadcrumbs.count { |crumb| crumb["category"].to_s == category }
  end

  def breadcrumb_level_prefix(crumb)
    LOUD_LEVELS[crumb["level"].to_s]
  end

  # sql → the statement; http → "200 · 212ms"; others → "key: value" pairs.
  def breadcrumb_details(crumb)
    data = crumb["data"].is_a?(Hash) ? crumb["data"] : {}
    case crumb["category"].to_s
    when "sql" then data["sql"].to_s
    when "http" then [ data["status"], (data["duration_ms"] && "#{data['duration_ms']}ms") ].compact_blank.join(" · ")
    else data.map { |key, value| "#{key}: #{context_text(value)}" }.join(" · ")
    end
  end
end
