ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/apm_fixture_stats"
require_relative "test_helpers/mcp_test_helper"
require_relative "test_helpers/migration_test_helper"

# Freezes the clock at the instant the APM fixtures were built from
# (ApmFixtureStats::ANCHOR) for the whole test. Include it in every test that
# reads APM stats or traces; otherwise a minute or hour boundary passing during
# the run moves the windows and the counts no longer match the fixtures.
module ApmFixtureClock
  extend ActiveSupport::Concern

  included do
    setup { travel_to ApmFixtureStats::ANCHOR }
  end
end

# Raw API key tokens for the api_keys fixtures (the fixtures store them
# encrypted plus a SHA-256 digest). Use these to authenticate ingest requests.
FIXTURE_TOKENS = {
  storefront_production: "gs_live_StorefrontProductionFixtureToken0001",
  storefront_staging: "gs_test_StorefrontStagingFixtureToken000001",
  marketing_production: "gs_live_MarketingProductionFixtureToken00001",
  umbrella_production: "gs_live_UmbrellaProductionFixtureToken000001"
}.freeze

# Raw personal access tokens for the personal_access_tokens fixtures (stored
# as SHA-256 digests only). Use these to authenticate MCP requests.
PAT_FIXTURE_TOKENS = {
  philip_read: "gs_pat_PhilipReadFixtureToken000000000000000000",
  philip_triage: "gs_pat_PhilipTriageFixtureToken0000000000000000",
  philip_full: "gs_pat_PhilipFullFixtureToken00000000000000000",
  jo_read: "gs_pat_JoReadFixtureToken0000000000000000000000",
  philip_expired: "gs_pat_PhilipExpiredFixtureToken000000000000000",
  philip_revoked: "gs_pat_PhilipRevokedFixtureToken000000000000000",
  outsider_read: "gs_pat_OutsiderReadFixtureToken00000000000000"
}.freeze

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Hosted mode is read once at boot into config.x.hosted (docs/ARCHITECTURE.md §12.2).
    def with_hosted_mode(hosted = true)
      previous = Rails.configuration.x.hosted
      Rails.configuration.x.hosted = hosted
      yield
    ensure
      Rails.configuration.x.hosted = previous
    end

    # GOODSORCERY_UPGRADE_URL is read once at boot into config.x.upgrade_url;
    # nil means no upgrade is offered and hosted limits say "coming soon".
    def with_upgrade_url(url = "https://billing.example/upgrade")
      previous = Rails.configuration.x.upgrade_url
      Rails.configuration.x.upgrade_url = url
      yield
    ensure
      Rails.configuration.x.upgrade_url = previous
    end

    # GOODSORCERY_TERMS_URL and GOODSORCERY_PRIVACY_URL are read once at boot
    # into config.x.terms_url and config.x.privacy_url; nil means unset.
    def with_legal_urls(terms: nil, privacy: nil)
      previous = [ Rails.configuration.x.terms_url, Rails.configuration.x.privacy_url ]
      Rails.configuration.x.terms_url = terms
      Rails.configuration.x.privacy_url = privacy
      yield
    ensure
      Rails.configuration.x.terms_url, Rails.configuration.x.privacy_url = previous
    end

    # The test cache store is a null store; this swaps in a real one.
    def with_memory_cache
      previous = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = previous
    end

    # Counts events toward this UTC month's total (the monthly quota) in an
    # environment no fixture rolls up, so the total doesn't depend on the date.
    def add_events_this_month(project, count)
      ProjectHourlyCount.create!(project:, environment: "quota-test", hour: Time.current.utc.beginning_of_hour, count:)
    end
  end
end
