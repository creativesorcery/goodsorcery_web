require "uri"

# The instance's public URL from GOODSORCERY_PUBLIC_URL, read at boot. It
# sets the host of links in emails (password resets) and the hosts the app
# answers to, so production refuses to boot without it.
#
#   url = PublicUrl.from_env(ENV, required: true)
#   url.url_options # => { host: "errors.example.com", protocol: "https" }
class PublicUrl
  VARIABLE = "GOODSORCERY_PUBLIC_URL".freeze
  EXTRA_HOSTS = "GOODSORCERY_EXTRA_HOSTS".freeze
  PLACEHOLDER = "http://localhost".freeze

  class Missing < StandardError; end

  # Without the variable: an error when required, else a localhost
  # placeholder (asset builds run without runtime configuration).
  def self.from_env(env, required:)
    url = env[VARIABLE].to_s.strip
    raise Missing, "Set #{VARIABLE} to this instance's public URL, e.g. https://errors.example.com" if url.empty? && required

    new(url.empty? ? PLACEHOLDER : url, extra_hosts: env[EXTRA_HOSTS])
  end

  attr_reader :uri

  def initialize(url, extra_hosts: nil)
    @uri = URI(url)
    raise Missing, "#{VARIABLE} must be an http(s) URL with a host" unless uri.is_a?(URI::HTTP) && uri.host.to_s != ""

    @extra_hosts = extra_hosts.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def host = uri.host

  # For config.action_mailer.default_url_options; the port only when non-standard.
  def url_options
    { host:, protocol: uri.scheme, port: (uri.port unless uri.port == uri.default_port) }.compact
  end

  # For config.hosts: the public host plus GOODSORCERY_EXTRA_HOSTS (comma-separated).
  def allowed_hosts = [ host, *@extra_hosts ].uniq

  def to_s = uri.to_s.delete_suffix("/")
end
