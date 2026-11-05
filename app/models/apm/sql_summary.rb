# Reads a normalised SQL statement from a trace for display
# (docs/ARCHITECTURE.md §13.9): a short label for the timeline, the first
# table it reads, and the statement split into one clause per line with
# its keywords and placeholders marked. The SQL is captured data: callers
# render the pieces through ERB escaping only (PerformanceHelper).
#
#   summary = Apm::SqlSummary.new('SELECT "users".* FROM "users" WHERE "users"."id" = $1 LIMIT $2')
#   summary.label  # => 'SELECT "users" WHERE "id" = $1'
#   summary.table  # => "users"
#   summary.lines  # => [[[:keyword, "SELECT"], [:text, " "], …], [[:keyword, "WHERE"], …]]
class Apm::SqlSummary
  LABEL_LIMIT = 90
  TOKEN = /"(?:[^"]|"")*"|'(?:[^']|'')*'|\$\d+|\?|[A-Za-z_][\w$]*|\s+|./m
  KEYWORDS = %w[
    SELECT FROM WHERE AND OR NOT IN IS NULL LIMIT OFFSET ORDER BY GROUP HAVING JOIN INNER LEFT RIGHT OUTER FULL CROSS ON AS
    INSERT INTO VALUES UPDATE SET DELETE RETURNING DISTINCT ASC DESC CASE WHEN THEN ELSE END BETWEEN LIKE ILIKE EXISTS
    UNION ALL CONFLICT DO NOTHING WITH FOR TRUE FALSE COUNT SUM MIN MAX ANY BEGIN COMMIT ROLLBACK SAVEPOINT RELEASE
  ].to_set.freeze
  BREAKS = %w[WHERE GROUP HAVING ORDER VALUES SET RETURNING UNION JOIN INNER LEFT RIGHT FULL CROSS].to_set.freeze
  JOIN_MODIFIERS = %w[INNER LEFT RIGHT FULL CROSS OUTER].to_set.freeze
  VERB_LABELS = { "SELECT" => "SELECT %s", "INSERT" => "INSERT INTO %s", "UPDATE" => "UPDATE %s", "DELETE" => "DELETE FROM %s" }.freeze
  WHERE_CLAUSE = /\bWHERE\s+(.+?)(?=\s+(?:ORDER\s+BY|GROUP\s+BY|LIMIT|OFFSET|RETURNING|FOR\s+UPDATE)\b|\z)/i

  attr_reader :sql

  def initialize(sql)
    @sql = sql.to_s.squish
  end

  # 'SELECT "users" WHERE "id" = $1', 'UPDATE "inventory_levels" WHERE "sku" IN (?)';
  # other statements are shortened as they are.
  def label
    format = VERB_LABELS[verb]
    return sql.truncate(LABEL_LIMIT) unless format && quoted_table

    [ Kernel.format(format, quoted_table), (where && "WHERE #{where}") ].compact.join(" ").truncate(LABEL_LIMIT)
  end

  # The first table read (FROM), unquoted and without its schema, or nil.
  def table = sql[/\bFROM\s+(?:"?\w+"?\.)?"?(\w+)"?/i, 1]

  # [[[type, text], …], …] per line; type is :keyword, :placeholder or :text.
  def lines
    tokens.each_with_object([ [] ]) do |token, result|
      result << [] if line_break?(token, result.last)
      result.last << classify(token) unless token.blank? && result.last.empty?
    end.map { |line| trim_trailing_space(line) }.reject(&:empty?)
  end

  private
    def verb = sql[/\A\w+/].to_s.upcase

    def quoted_table = sql[/\b(?:FROM|INTO|UPDATE)\s+((?:"[^"]+"\.)?(?:"[^"]+"|\w+))/i, 1]&.sub(/\A"[^"]+"\./, "")

    def where = sql[WHERE_CLAUSE, 1]&.gsub(/"[^"]+"\./, "")

    def tokens = sql.scan(TOKEN).map { it.match?(/\A\s+\z/) ? " " : it }

    def line_break?(token, line)
      word = token.upcase
      return false unless BREAKS.include?(word) && line.any?

      !(word == "JOIN" && JOIN_MODIFIERS.include?(previous_word(line)))
    end

    def trim_trailing_space(line)
      line = line.dup
      line.pop while line.last&.last == " "
      line
    end

    def previous_word(line) = line.reverse.find { |_, text| text.present? }&.last.to_s.upcase

    def classify(token)
      return [ :keyword, token ] if KEYWORDS.include?(token.upcase) && token.match?(/\A[A-Za-z]/)
      return [ :placeholder, token ] if token.match?(/\A(?:\$\d+|\?)\z/)

      [ :text, token ]
    end
end
