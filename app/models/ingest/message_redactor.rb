# Produces the plaintext, searchable issue title from an exception message by
# replacing likely-personal fragments with placeholders (ARCHITECTURE.md §1.5).
# The full message is kept only in the encrypted occurrence payload.
#
# The same rules (minus the number rule) keep personal data out of the other
# plaintext columns, the transaction name and the culprit.
class Ingest::MessageRedactor
  # Shapes that dump whole values: PG row and key details, `'column'=value`
  # lookups, `= 'value'` comparisons and quoted values after with/for.
  VALUE_RULES = [
    [ /Failing row contains \(.*\)/, "Failing row contains ([row])" ],
    [ /\bKey \(([^)]*)\)=\(.*?\)(?=\s|\.|,|\z)/, 'Key (\1)=([value])' ],
    [ /('[\w.]+')=(?:'[^']*'|"[^"]*"|[^\s,)]+)/, '\1=[value]' ],
    [ /=\s*(?:'[^']*'|"[^"]*")/, "=[value]" ],
    [ /\b(with|for|named|called)\s+(['"])[^'"\n]*\2(?!\s*=)/i, '\1 [value]' ]
  ].freeze

  IDENTITY_RULES = [
    [ /[\w.%+-]+@[\w-]+(?:\.[\w-]+)+/, "[email]" ],
    [ %r{(/[^\s?#"']*)\?[^\s#"']+}, '\1?[query]' ],
    [ /\b\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\b/, "[uuid]" ],
    [ /\b(?:\d{1,3}\.){3}\d{1,3}\b/, "[ip]" ],
    [ /\b\h{16,}\b/, "[token]" ],
    [ /(?<![\w-])(?=[\w-]*\d)(?=[\w-]*[A-Za-z])[\w-]{16,}={0,2}/, "[token]" ]
  ].freeze

  NUMBER_RULE = [ /\b\d{2,}\b/, "[n]" ].freeze

  RULES = [ *VALUE_RULES, *IDENTITY_RULES, NUMBER_RULE ].freeze

  def redact(message)
    apply(RULES, message).squish.truncate(Ingest::Limits::TITLE, omission: "…")
  end

  # For a transaction name such as "GET /users/mara@example.com/reset?x=1".
  def redact_transaction(name)
    apply(RULES, name).squish.presence
  end

  # For a culprit ("app/models/user.rb:42 in find"): line numbers are kept.
  def redact_location(location)
    apply([ *VALUE_RULES, *IDENTITY_RULES ], location).presence
  end

  private
    def apply(rules, text)
      rules.reduce(text.to_s) { |result, (pattern, replacement)| result.gsub(pattern, replacement) }
    end
end
