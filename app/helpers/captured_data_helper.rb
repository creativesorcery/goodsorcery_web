# Rendering of values captured with an error (locals, breadcrumb data,
# request, params, headers, session, context). Everything here may touch
# decrypted occurrence data, so it only ever builds escaped tags (tag.span /
# safe_join): never raw, html_safe or sanitize, and nothing is ever cached.
module CapturedDataHelper
  FILTERED = "[FILTERED]".freeze
  JSON_TOKENS = /"(?:\\.|[^"\\])*"|-?\d[\d.eE+-]*|true|false|null|[\s{}\[\],:]+|./m

  # A scalar from captured data; "[FILTERED]" renders muted.
  def context_value(value, tone: "text-ink-100")
    text = context_text(value)
    tag.span(text, class: text == FILTERED ? "text-ink-400" : tone)
  end

  def context_text(value)
    value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
  end

  # Pretty JSON with token colours, built from escaped spans only.
  def pretty_json(value)
    safe_join(JSON.pretty_generate(value).scan(JSON_TOKENS).map { |token| json_token(token) })
  end

  private
    def json_token(token)
      return tag.span(FILTERED, class: "text-ink-400") if token == "\"#{FILTERED}\""
      return tag.span(token, class: "tok-s") if token.start_with?('"')
      return tag.span(token, class: "tok-n") if token.match?(/\A(-?\d|true|false|null)/)

      token
    end
end
