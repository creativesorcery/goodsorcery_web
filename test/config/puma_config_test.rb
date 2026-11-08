require "test_helper"
require "puma/configuration"

# Puma reads a whole request body before Rack runs, so without a server cap an
# unauthenticated client could make it buffer any amount before the ingest
# endpoints' own size checks or the rate limits ever see the request.
class PumaConfigTest < ActiveSupport::TestCase
  test "caps request bodies just above the largest ingest body" do
    limit = puma_options[:http_content_length_limit]

    assert_equal 4.megabytes, limit
    assert_operator limit, :>, [ Ingest::Limits::BATCH_BODY_BYTES, Apm::Limits::TRACES_BODY_BYTES ].max
  end

  private
    def puma_options
      Puma::Configuration.new(config_files: [ Rails.root.join("config/puma.rb").to_s ]).tap(&:clamp).options
    end
end
