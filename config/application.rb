require_relative "boot"

# Only the frameworks in use: no Active Storage, Action Mailbox or Action Text,
# whose engines would mount unauthenticated /rails/active_storage/* and
# /rails/action_mailbox/* endpoints.
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"
require_relative "../lib/middleware/ingest_body_shield"
require_relative "../lib/configuration/public_url"
require_relative "../lib/configuration/http_url"
require_relative "../lib/configuration/self_reporting_endpoint"
require_relative "../lib/configuration/ingest_shedding"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module GoodsorceryWeb
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks middleware configuration])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Keep the raw ingest body out of params and the request log.
    config.middleware.use IngestBodyShield

    # Every encrypted column must hold ciphertext; never read plaintext fallbacks.
    config.active_record.encryption.support_unencrypted_data = false

    # Hosted mode (docs/ARCHITECTURE.md §12.2). Self-hosted, the default, makes
    # every entitlement unlimited; hosted reads each account's stored values and
    # falls back to the hosted defaults in config/entitlements.yml.
    config.x.hosted = ActiveModel::Type::Boolean.new.cast(ENV["GOODSORCERY_HOSTED"]) || false
    config.x.upgrade_url = ENV["GOODSORCERY_UPGRADE_URL"].presence
    config.x.entitlements = config_for(:entitlements)

    # Optional legal pages the sign-up page links to; only http(s) URLs count,
    # and with neither set the page shows no agreement sentence at all.
    config.x.terms_url = HttpUrl.parse(ENV["GOODSORCERY_TERMS_URL"])
    config.x.privacy_url = HttpUrl.parse(ENV["GOODSORCERY_PRIVACY_URL"])

    # The instance's public URL (GOODSORCERY_PUBLIC_URL, required in
    # production), or nil. The MCP server page builds MCP client snippets
    # from it, and the MCP endpoint accepts browser Origins of it only.
    public_url = ENV[PublicUrl::VARIABLE].to_s.strip
    config.x.public_url = (PublicUrl.new(public_url) unless public_url.empty?)

    # Days of performance data a self-hosted instance keeps (1..30, default
    # 30); hosted accounts use their apm_retention_days entitlement instead.
    config.x.apm_retention_days = (ENV["GOODSORCERY_APM_RETENTION_DAYS"].presence || 30).to_i.clamp(1, 30)

    # Local testing of uptime checks against private addresses; never honoured in production.
    # Ingest counter buffer (docs/ARCHITECTURE.md §2.5.2): off here, so
    # development and test write counters straight to Postgres.
    # config/environments/production.rb turns it on.
    config.x.counter_buffer_url = nil
    config.x.counter_buffer_enabled = false

    config.x.uptime.allow_private_addresses =
      ENV["GOODSORCERY_UPTIME_ALLOW_PRIVATE_ADDRESSES"] == "1" && !Rails.env.production?

    # Uptime: a failed check takes a monitor down only when a second check,
    # CONFIRM_AFTER later, fails too (UptimeMonitor::Checking). Off by default.
    config.x.uptime.confirm_down =
      %w[1 true yes on].include?(ENV["GOODSORCERY_UPTIME_CONFIRM_DOWN"].to_s.strip.downcase)

    # Backlog-aware ingest admission (Ingest::Backlog): the ingest queue
    # latency, in seconds, at which ingest starts (0: never) and stops
    # answering 429 server_busy. Invalid values fall back to the defaults.
    ingest_shedding = IngestShedding.from_env(ENV)
    warn "Ignoring invalid ingest shedding settings: #{ingest_shedding.problem}. Using the defaults." if ingest_shedding.problem
    config.x.ingest.shed_after_seconds = ingest_shedding.shed_after
    config.x.ingest.resume_below_seconds = ingest_shedding.resume_below

    # Where Ingest::QueueLatency reads the ingest queue: the Redis Sidekiq
    # connects to. With no Sidekiq initializer, that is the variable named by
    # REDIS_PROVIDER, else REDIS_URL (Sidekiq::RedisConnection); without
    # either, Sidekiq's own localhost default. A future Sidekiq initializer
    # that sets `config.redis` (TLS, a password) must set these options too,
    # or every latency read fails and ingest never sheds.
    config.x.ingest.queue_redis_options = { url: ENV[ENV["REDIS_PROVIDER"].to_s] || ENV["REDIS_URL"] }.compact
  end
end
