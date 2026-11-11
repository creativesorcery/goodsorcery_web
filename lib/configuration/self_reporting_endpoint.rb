# Where this instance sends its own errors (config/initializers/goodsorcery.rb).
# GOODSORCERY_ENDPOINT always wins. Otherwise the hosted service reports to
# itself, and a self-hosted instance to its own GOODSORCERY_PUBLIC_URL. A
# self-hosted instance with neither gets nil, and self-reporting stays off:
# its errors (request params, headers, user context) must never go to the
# hosted service just because GOODSORCERY_API_KEY was set.
#
#   SelfReportingEndpoint.from_env(ENV, hosted: false) # => "https://errors.example.com" or nil
module SelfReportingEndpoint
  HOSTED = "https://app.goodsorcery.com".freeze

  def self.from_env(env, hosted:)
    explicit = env["GOODSORCERY_ENDPOINT"].to_s.strip
    return explicit unless explicit.empty?
    return HOSTED if hosted

    public_url = env["GOODSORCERY_PUBLIC_URL"].to_s.strip
    public_url unless public_url.empty?
  end
end
