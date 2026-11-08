require "test_helper"

class IngestBodyShieldTest < ActiveSupport::TestCase
  setup do
    @seen = nil
    @shield = IngestBodyShield.new(->(env) { @seen = env; [ 200, {}, [] ] })
  end

  test "blanks request parameters for the ingest path and its variants" do
    [ "/api/v1/events", "/api/v1/events/", "/api//v1//events", "/api/v1/events.json",
      "/api/v1/events/batch", "/api/v1/events/batch/", "/api//v1//events//batch", "/api/v1/events/batch.json",
      "/mcp", "/mcp/", "/mcp.json" ].each do |path|
      @shield.call(Rack::MockRequest.env_for(path, method: "POST", input: '{"user":"mara@example.com"}'))
      assert_equal({}, @seen["action_dispatch.request.request_parameters"], path)
    end
  end

  test "leaves other paths alone" do
    [ "/session", "/api/v1/events/123", "/api/v1/eventsx", "/api/v1/events/batchx", "/api/v1/events/batch/1",
      "/mcpx", "/mcp/1", "/access_tokens" ].each do |path|
      @shield.call(Rack::MockRequest.env_for(path, method: "POST"))
      assert_not @seen.key?("action_dispatch.request.request_parameters"), path
    end
  end

  test "shields every spelling that routes to an ingest controller" do
    [ "/api/v1/events", "/api//v1/events/", "/api/v1/events.json", "/api/v1/events/batch", "/api/v1//events/batch/",
      "/api/v1/events/batch.json" ].each do |path|
      route = Rails.application.routes.recognize_path(path, method: :post)
      assert_match %r{\Aapi/v1/events}, route[:controller], path
      @shield.call(Rack::MockRequest.env_for(path, method: "POST"))
      assert_equal({}, @seen["action_dispatch.request.request_parameters"], path)
    end
  end

  test "shields every spelling that routes to the MCP endpoint" do
    # PATH_INFO is set directly: env_for would read "//mcp/" as a host.
    [ "/mcp", "//mcp/", "/mcp.json" ].each do |path|
      assert_equal "mcp", Rails.application.routes.recognize_path(path, method: :post)[:controller], path
      @shield.call(Rack::MockRequest.env_for("/", method: "POST").merge("PATH_INFO" => path))
      assert_equal({}, @seen["action_dispatch.request.request_parameters"], path)
    end
  end

  test "is installed in the middleware stack" do
    assert_includes Rails.application.middleware.map(&:klass), IngestBodyShield
  end
end
