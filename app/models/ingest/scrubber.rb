# Server-side scrubbing, the second line of defence after the client's own
# filter_parameters. Values under sensitive keys become "[FILTERED]", and
# secrets embedded in any string are replaced in place: card numbers,
# credentials (Bearer, Basic, Digest, ApiKey, Token), JWTs, sensitive URL
# query parameters, URL passwords, and sensitive keys written as free text
# (`password=x`, `api_key: x`, `"token"=>"x"`, `"secret": "x"`).
class Ingest::Scrubber
  FILTERED = "[FILTERED]".freeze

  KEY_PATTERN = /passw|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|authorization|cookie|csrf|xsrf|
    credit[_-]?card|card[_-]?number|(?<![a-z])(?:cvv|cvc|ssn|otp)(?![a-z])|session[_-]?id/ix

  # A card-like digit run, or a whole identifier: a UUID, or a word of 20+
  # hex characters with at least one letter (Sidekiq job ids, Mongo ids, git
  # SHAs). Matching identifiers first keeps the digit runs inside job,
  # request and provider job ids from being taken for card numbers.
  CARD_NUMBER_OR_ID = /(?<id>(?<!\h)\h{8}-\h{4}-\h{4}-\h{4}-\h{12}(?!\h)|(?<!\w)(?=\h*[a-f])\h{20,}(?!\w))|
    (?<!\d)\d(?:[ -]?\d){12,18}(?!\d)/xi
  CREDENTIAL = /\b(Bearer|Basic|Digest|ApiKey)\s+[^\s"',;]+/i
  # "Token" is also an ordinary word, so only token-like values (with a digit) go.
  TOKEN_CREDENTIAL = /\b(Token)\s+(?=[^\s"',;]*\d)[^\s"',;]+/i
  JWT = /eyJ[\w-]+\.[\w-]+\.[\w-]+/
  QUERY_PARAM = /([?&;])([^=&#\s?;]+)=([^&#\s;"']*)/
  URL_PASSWORD = %r{(\b[a-z][a-z0-9+.-]*://[^:/\s@]*:)[^@\s/]+@}i
  # A free-text key (optionally quoted), =, => or a single colon, and the
  # value: quoted, or bare up to a delimiter, with an optional credential
  # scheme ("Authorization: Token abc"). Atomic groups keep matching linear.
  FREE_TEXT_PAIR = /(?<key>(?<q>["']?)(?<![\w.-])(?<name>(?>[\w.-]+))\k<q>)(?<separator>\s*(?:=>|=(?!=)|(?<!:):(?!:))\s*)
    (?<value>(?>"(?:[^"\\]|\\.)*")|(?>'[^']*')|(?:(?:Bearer|Basic|Digest|ApiKey|Token)\s+)?(?:\[FILTERED\]|(?>[^\s,;&}\])"']+)))/xi
  # An unquoted CamelCase name is a class, as in "InvalidAuthenticityToken: Can't verify".
  CLASS_NAME = /\A[A-Z]\w*[a-z][A-Z]/

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
    text = scrub_card_numbers(text)
    text = text.gsub(CREDENTIAL) { "#{$1} #{FILTERED}" }.gsub(TOKEN_CREDENTIAL) { "#{$1} #{FILTERED}" }.gsub(JWT, FILTERED)
    text = text.gsub(QUERY_PARAM) { sensitive_key?($2) ? "#{$1}#{$2}=#{FILTERED}" : $& }
    scrub_free_text_keys(text.gsub(URL_PASSWORD) { "#{$1}#{FILTERED}@" })
  end

  def sensitive_key?(key)
    key = key.to_s
    key.match?(KEY_PATTERN) || @extra_keys.any? { |extra| key.downcase.include?(extra) }
  end

  private
    def scrub_card_numbers(text)
      text.gsub(CARD_NUMBER_OR_ID) { |found| $~[:id] || !Ingest::Luhn.valid?(found) ? found : FILTERED }
    end

    def scrub_hash(hash)
      hash.to_h { |key, value| [ key, sensitive_key?(key) ? FILTERED : scrub(value) ] }
    end

    # Keeps the key, separator and any quotes; replaces only the value.
    def scrub_free_text_keys(text)
      text.gsub(FREE_TEXT_PAIR) do
        match = $~
        next match[0] unless sensitive_free_text_key?(match)

        quote = match[:value][0].then { |first| %w[" '].include?(first) ? first : "" }
        "#{match[:key]}#{match[:separator]}#{quote}#{FILTERED}#{quote}"
      end
    end

    def sensitive_free_text_key?(match)
      sensitive_key?(match[:name]) && !(match[:q].empty? && match[:name].match?(CLASS_NAME))
    end
end
