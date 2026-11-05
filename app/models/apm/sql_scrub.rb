# Server-side SQL normalisation for trace spans (docs/ARCHITECTURE.md §13.5),
# repeating the gem's rules as a second layer: comments removed; string,
# dollar-quoted and numeric literals become "?"; IN lists of placeholders
# collapse to "IN (…)"; repeated VALUES rows collapse; whitespace collapses.
# Bind placeholders ($1), quoted identifiers, TRUE/FALSE/NULL stay. Then
# Ingest::Scrubber's string scrubbing runs over what is left.
class Apm::SqlScrub
  TOKEN = /
    (?<comment>\/\*.*?(?:\*\/|\z)|--[^\n]*)
    |(?<dollar>\$(?<tag>[a-z_]\w*)?\$.*?(?:\$\k<tag>?\$|\z))
    |(?<string>[eE]?'(?:''|\\.|[^'\\])*(?:'|\z))
    |(?<identifier>"(?:""|[^"])*"?)
    |(?<placeholder>\$\d+)
    |(?<word>[a-z_][\w$]*)
    |(?<number>(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)
  /xim
  IN_LIST = /\bIN\s*\(\s*(?:\?|\$\d+)(?:\s*,\s*(?:\?|\$\d+))*\s*\)/i
  VALUES_ROWS = /(\bVALUES\s*(\([^()]*\)))(?:\s*,\s*\([^()]*\))+/i

  def initialize(scrubber: Ingest::Scrubber.new)
    @scrubber = scrubber
  end

  def scrub(sql)
    text = sql.to_s.first(Apm::Limits::SQL * 2).gsub(TOKEN) { replacement($~) }
    text = text.gsub(IN_LIST, "IN (…)").gsub(VALUES_ROWS) { "#{$1}, …" }
    @scrubber.scrub_text(text.squish).first(Apm::Limits::SQL)
  end

  private
    def replacement(match)
      return " " if match[:comment]
      return "?" if match[:dollar] || match[:string] || match[:number]

      match[0]
    end
end
