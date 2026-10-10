require_relative "boot"

require "rails/all"
require_relative "../lib/middleware/ingest_body_shield"
require_relative "../lib/configuration/public_url"

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
  end
end
