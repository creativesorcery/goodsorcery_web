ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

# Raw API key tokens for the api_keys fixtures (the fixtures store them
# encrypted plus a SHA-256 digest). Use these to authenticate ingest requests.
FIXTURE_TOKENS = {
  storefront_production: "gs_live_StorefrontProductionFixtureToken0001",
  storefront_staging: "gs_test_StorefrontStagingFixtureToken000001",
  marketing_production: "gs_live_MarketingProductionFixtureToken00001",
  umbrella_production: "gs_live_UmbrellaProductionFixtureToken000001"
}.freeze

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
