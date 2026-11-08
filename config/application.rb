require_relative "boot"

require "rails/all"
require_relative "../lib/middleware/ingest_body_shield"
require_relative "../lib/configuration/public_url"
require_relative "../lib/configuration/http_url"

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

    # Days of performance data a self-hosted instance keeps (1..30, default
    # 30); hosted accounts use their apm_retention_days entitlement instead.
    config.x.apm_retention_days = (ENV["GOODSORCERY_APM_RETENTION_DAYS"].presence || 30).to_i.clamp(1, 30)

    # Local testing of uptime checks against private addresses; never honoured in production.
    config.x.uptime.allow_private_addresses =
      ENV["GOODSORCERY_UPTIME_ALLOW_PRIVATE_ADDRESSES"] == "1" && !Rails.env.production?
  end
end
