require "uri"

# An optional http(s) URL from an environment variable, read at boot. Blank
# means unset, and anything that isn't an absolute http(s) URL with a host
# (javascript:, mailto:, a bare path, a typo) is ignored, so it can be put
# straight into an href.
#
#   HttpUrl.parse(ENV["GOODSORCERY_TERMS_URL"]) # => "https://example.com/terms" or nil
module HttpUrl
  def self.parse(value)
    url = value.to_s.strip
    uri = URI(url)
    url if uri.is_a?(URI::HTTP) && uri.host.to_s != ""
  rescue URI::InvalidURIError
    nil
  end
end
