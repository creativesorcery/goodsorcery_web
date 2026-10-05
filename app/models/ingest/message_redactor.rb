# Produces the plaintext, searchable issue title from an exception message by
# replacing likely-personal fragments with placeholders (ARCHITECTURE.md §1.5).
# The full message is kept only in the encrypted occurrence payload.
class Ingest::MessageRedactor
  RULES = [
    [ /[\w.%+-]+@[\w-]+(?:\.[\w-]+)+/, "[email]" ],
    [ %r{(\b[a-z][a-z0-9+.-]*://[^\s?#]+)\?[^\s#]*}i, '\1?[query]' ],
    [ /\b\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\b/, "[uuid]" ],
    [ /\b(?:\d{1,3}\.){3}\d{1,3}\b/, "[ip]" ],
    [ /\b\h{16,}\b/, "[token]" ],
    [ /(?<![\w-])(?=[\w-]*\d)(?=[\w-]*[A-Za-z])[\w-]{16,}={0,2}/, "[token]" ],
    [ /\b\d{2,}\b/, "[n]" ]
  ].freeze

  def redact(message)
    redacted = RULES.reduce(message.to_s) { |text, (pattern, replacement)| text.gsub(pattern, replacement) }
    redacted.squish.truncate(Ingest::Limits::TITLE, omission: "…")
  end
end
