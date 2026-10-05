# Server-side scrubbing, the second line of defence after the client's own
# filter_parameters. Values under sensitive keys become "[FILTERED]", and
# secrets embedded in any string (card numbers, bearer credentials, JWTs,
# sensitive URL query parameters, URL passwords) are replaced in place.
class Ingest::Scrubber
  FILTERED = "[FILTERED]".freeze

  KEY_PATTERN = /passw|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|authorization|cookie|csrf|xsrf|
    credit[_-]?card|card[_-]?number|(?<![a-z])(?:cvv|cvc|ssn|otp)(?![a-z])|session[_-]?id/ix

  CARD_NUMBER = /(?<!\d)\d(?:[ -]?\d){12,18}(?!\d)/
  CREDENTIAL = /\b(Bearer|Basic)\s+[^\s"',;]+/i
  JWT = /eyJ[\w-]+\.[\w-]+\.[\w-]+/
  QUERY_PARAM = /([?&;])([^=&#\s?;]+)=([^&#\s;"']*)/
  URL_PASSWORD = %r{(\b[a-z][a-z0-9+.-]*://[^:/\s@]+:)[^@\s/]+@}i

  def initialize(extra_keys: [])
    @extra_keys = Array(extra_keys).map { |key| key.to_s.downcase }.compact_blank
  end

  # Deep-scrubs hashes, arrays and strings; other scalars pass through.
  def scrub(value)
    case value
    when Hash then scrub_hash(value)
    when Array then value.map { |item| scrub(item) }
    when String then scrub_text(value)
    else value
    end
  end

  def scrub_text(text)
    text = text.gsub(CARD_NUMBER) { |digits| Ingest::Luhn.valid?(digits) ? FILTERED : digits }
    text = text.gsub(CREDENTIAL) { "#{$1} #{FILTERED}" }.gsub(JWT, FILTERED)
    text.gsub(QUERY_PARAM) { sensitive_key?($2) ? "#{$1}#{$2}=#{FILTERED}" : $& }
        .gsub(URL_PASSWORD) { "#{$1}#{FILTERED}@" }
  end

  def sensitive_key?(key)
    key = key.to_s
    key.match?(KEY_PATTERN) || @extra_keys.any? { |extra| key.downcase.include?(extra) }
  end

  private
    def scrub_hash(hash)
      hash.to_h { |key, value| [ key, sensitive_key?(key) ? FILTERED : scrub(value) ] }
    end
end
