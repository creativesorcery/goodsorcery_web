require "test_helper"

class IngestBodyShieldTest < ActiveSupport::TestCase
  setup do
    @seen = nil
    @shield = IngestBodyShield.new(->(env) { @seen = env; [ 200, {}, [] ] })
  end

  test "blanks request parameters for the ingest path and its variants" do
    [ "/api/v1/events", "/api/v1/events/", "/api//v1//events", "/api/v1/events.json" ].each do |path|
      @shield.call(Rack::MockRequest.env_for(path, method: "POST", input: '{"user":"mara@example.com"}'))
      assert_equal({}, @seen["action_dispatch.request.request_parameters"], path)
    end
  end

  test "leaves other paths alone" do
    [ "/session", "/api/v1/events/123", "/api/v1/eventsx" ].each do |path|
      @shield.call(Rack::MockRequest.env_for(path, method: "POST"))
      assert_not @seen.key?("action_dispatch.request.request_parameters"), path
    end
  end

  test "is installed in the middleware stack" do
    assert_includes Rails.application.middleware.map(&:klass), IngestBodyShield
  end
end
