# Server-side SQL normalisation for trace spans (docs/ARCHITECTURE.md §13.5),
# repeating the gem's rules as a second layer: comments removed; string,
# dollar-quoted and numeric (also 0x hex) literals become "?"; IN lists of
# placeholders collapse to "IN (…)"; repeated VALUES rows collapse;
# whitespace collapses. Bind placeholders ($1), quoted identifiers,
# TRUE/FALSE/NULL stay. Then Ingest::Scrubber's string scrubbing runs over
# what is left.
#
# The server doesn't know the client's database, and a backslash escapes a
# quote in MySQL strings but not in standard Postgres ones. The SQL is read
# both ways (E'…' strings always honour backslashes); when the two readings
# disagree, everything from the first string holding a backslash on becomes
# one "?", so a misread quote never leaves a literal value in the text.
class Apm::SqlScrub
  PARTS = {
    comment: %r{/\*.*?(?:\*/|\z)|--[^\n]*},
    dollar: /\$(?<tag>(?:[a-z_]\w*)?)\$.*?(?:\$\k<tag>\$|\z)/,
    escape_string: /(?<![\w$])[eE]'(?:''|\\.|[^'\\])*(?:'|\z)/,
    identifier: /"(?:""|[^"])*"?/,
    placeholder: /\$\d+/,
    word: /[a-z_][\w$]*/,
    number: /(?<![\w$])(?:0x[0-9a-f]+|(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)/
  }.freeze
  STANDARD_STRING = /'(?:''|[^'])*(?:'|\z)/
  BACKSLASH_STRING = /'(?:''|\\.|[^'\\])*(?:'|\z)/

  def self.token(string)
    parts = PARTS.to_a.insert(3, [ :string, string ])
    Regexp.new(parts.map { |name, pattern| "(?<#{name}>#{pattern.source})" }.join("|"), Regexp::IGNORECASE | Regexp::MULTILINE)
  end

  TOKEN = token(STANDARD_STRING)
  BACKSLASH_TOKEN = token(BACKSLASH_STRING)
  LITERALS = %i[dollar escape_string string number].freeze
  IN_LIST = /\bIN\s*\(\s*(?:\?|\$\d+)(?:\s*,\s*(?:\?|\$\d+))*\s*\)/i
  VALUES_ROWS = /(\bVALUES\s*(\([^()]*\)))(?:\s*,\s*\([^()]*\))+/i

  def initialize(scrubber: Ingest::Scrubber.new)
    @scrubber = scrubber
  end

  def scrub(sql)
    text = without_literals(sql.to_s.first(Apm::Limits::SQL * 2))
    text = text.gsub(IN_LIST, "IN (…)").gsub(VALUES_ROWS) { "#{$1}, …" }
    @scrubber.scrub_text(text.squish).first(Apm::Limits::SQL)
  end

  private
    def without_literals(sql)
      standard = replace_literals(sql, TOKEN)
      return standard unless sql.include?("\\") && standard != replace_literals(sql, BACKSLASH_TOKEN)

      cut = ambiguous_string_start(sql)
      "#{replace_literals(sql[0...cut], TOKEN)} ?"
    end

    def replace_literals(sql, token) = sql.gsub(token) { replacement($~) }

    # Where the readings part: the first standard string holding a backslash.
    def ambiguous_string_start(sql)
      sql.to_enum(:scan, TOKEN).map { $~ }.find { it[:string]&.include?("\\") }&.begin(0) || 0
    end

    def replacement(match)
      return " " if match[:comment]
      return "?" if LITERALS.any? { match[it] }

      match[0]
    end
end
