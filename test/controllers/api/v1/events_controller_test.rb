require "test_helper"
require_relative "../../../models/ingest/ingest_test_support"

class Api::V1::EventsControllerTest < ActionDispatch::IntegrationTest
  include IngestTestSupport
  include ActiveJob::TestHelper

  setup { @token = FIXTURE_TOKENS[:storefront_production] }

  def post_event(body = event_json, token: @token, headers: {})
    defaults = { "Content-Type" => "application/json" }
    defaults["Authorization"] = "Bearer #{token}" if token
    post api_v1_events_path, params: body, headers: defaults.merge(headers)
  end

  test "accepts an event: 202 with the event id, stores it encrypted and enqueues its id only" do
    assert_difference -> { InboundEvent.count }, 1 do
      post_event event_json("full", event_id: "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0dd4")
    end

    assert_response :accepted
    assert_equal({ "id" => "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0dd4" }, response.parsed_body)
    inbound = InboundEvent.order(:id).last
    assert_equal [ projects(:storefront).id, api_keys(:storefront_production).id, "production" ],
                 [ inbound.project_id, inbound.api_key_id, inbound.environment ]
    assert_not_includes raw_column(InboundEvent, :body, inbound.id), "mara"
    assert_enqueued_with(job: ProcessInboundEventJob, args: [ inbound ], queue: "ingest")
  end

  test "job arguments carry no payload content" do
    post_event
    serialized = enqueued_jobs.find { it[:job] == ProcessInboundEventJob }[:args].to_json
    assert_match %r{gid://[^"]+/InboundEvent/\d+}, serialized
    %w[mara NoMethodError price_cents hunter2 5521].each { |text| assert_not_includes serialized, text }
  end

  test "the body never reaches params or the request log" do
    seen = []
    callback = ->(*, payload) { seen << payload[:params] }
    ActiveSupport::Notifications.subscribed(callback, "start_processing.action_controller") { post_event }
    assert_equal({ "controller" => "api/v1/events", "action" => "create" }, seen.sole.stringify_keys)
  end

  test "accepts gzip bodies and charset parameters" do
    post_event ActiveSupport::Gzip.compress(minimal_json),
               headers: { "Content-Encoding" => "gzip", "Content-Type" => "application/json; charset=utf-8" }
    assert_response :accepted
  end

  test "generates an event id when the client sends none" do
    post_event minimal_json
    assert_match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/, response.parsed_body["id"])
  end

  test "records key usage" do
    api_keys(:storefront_staging).update_column(:last_used_at, nil)
    post_event minimal_json, token: FIXTURE_TOKENS[:storefront_staging]
    assert_not_nil api_keys(:storefront_staging).reload.last_used_at
  end

  test "an API key only ever writes to its own project and environment" do
    post_event minimal_json, token: FIXTURE_TOKENS[:umbrella_production]
    inbound = InboundEvent.order(:id).last
    assert_equal [ projects(:umbrella_app).id, "production" ], [ inbound.project_id, inbound.environment ]
  end

  test "401 for missing, malformed, unknown or rotated keys" do
    rotated = api_keys(:storefront_staging)
    rotated.rotate
    [ { token: nil }, { token: "gs_live_unknown" }, { token: FIXTURE_TOKENS[:storefront_staging] },
      { token: nil, headers: { "Authorization" => "Basic #{@token}" } },
      { token: nil, headers: { "Authorization" => @token } } ].each do |options|
      assert_no_difference(-> { InboundEvent.count }) { post_event(minimal_json, **options) }
      assert_response :unauthorized
      assert_equal({ "error" => "invalid_api_key" }, response.parsed_body)
      assert_equal 'Bearer realm="ingest"', response.headers["WWW-Authenticate"]
    end
  end

  test "415 for other content types and encodings" do
    post_event minimal_json, headers: { "Content-Type" => "text/plain" }
    assert_response :unsupported_media_type
    assert_equal({ "error" => "unsupported_media_type" }, response.parsed_body)

    post_event minimal_json, headers: { "Content-Encoding" => "br" }
    assert_response :unsupported_media_type
  end

  test "400 for malformed JSON, without echoing it" do
    [ '{"user":"mara@example.com"', "", ActiveSupport::Gzip.compress("{nope") ].each_with_index do |body, index|
      post_event body, headers: index == 2 ? { "Content-Encoding" => "gzip" } : {}
      assert_response :bad_request
      assert_equal({ "error" => "invalid_json" }, response.parsed_body)
    end
  end

  test "422 for valid JSON with the wrong shape, without echoing it" do
    post_event({ exception: { message: "mara@example.com" } }.to_json)
    assert_response :unprocessable_content
    assert_equal({ "error" => "invalid_payload", "messages" => [ "exception.class is required" ] }, response.parsed_body)

    post_event "[]"
    assert_equal [ "body must be a JSON object" ], response.parsed_body["messages"]
  end

  test "413 for oversized bodies, compressed or decompressed" do
    big = { exception: { class: "E", message: "x" * Ingest::Limits::BODY_BYTES } }.to_json
    assert_no_difference(-> { InboundEvent.count }) { post_event big }
    assert_response :content_too_large
    assert_equal({ "error" => "payload_too_large" }, response.parsed_body)

    post_event ActiveSupport::Gzip.compress(big), headers: { "Content-Encoding" => "gzip" }
    assert_response :content_too_large
  end

  test "auth runs before content checks" do
    post_event "nope", token: nil, headers: { "Content-Type" => "text/plain" }
    assert_response :unauthorized
  end

  class RateLimitTest < ActionDispatch::IntegrationTest
    include IngestTestSupport

    setup do
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown { Rails.cache = @original_cache }

    def post_event(token = FIXTURE_TOKENS[:storefront_production])
      post api_v1_events_path, params: minimal_json,
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    end

    test "429 with Retry-After once a key exceeds its limit" do
      key_id = api_keys(:storefront_production).id
      Rails.cache.increment("rate-limit:api/v1/events:key:#{key_id}", Ingest::Limits::RATE_PER_KEY, expires_in: 1.minute)

      assert_no_difference(-> { InboundEvent.count }) { post_event }
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
      assert_equal({ "error" => "rate_limited" }, response.parsed_body)

      post_event FIXTURE_TOKENS[:storefront_staging]
      assert_response :accepted, "other keys are unaffected"
    end

    test "429 once an IP exceeds its limit, before authentication" do
      Rails.cache.increment("rate-limit:api/v1/events:ip:127.0.0.1", Ingest::Limits::RATE_PER_IP, expires_in: 1.minute)
      post_event "gs_live_unknown"
      assert_response :too_many_requests
    end

    test "requests under the limits are counted and accepted" do
      2.times { post_event }
      assert_response :accepted
      assert_equal 2, Rails.cache.read("rate-limit:api/v1/events:key:#{api_keys(:storefront_production).id}", raw: true).to_i
    end
  end
end
