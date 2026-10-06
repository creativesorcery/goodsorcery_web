require "test_helper"
require_relative "../../../../models/ingest/ingest_test_support"

class Api::V1::Events::BatchesControllerTest < ActionDispatch::IntegrationTest
  include IngestTestSupport
  include ActiveJob::TestHelper

  setup { @token = FIXTURE_TOKENS[:storefront_production] }

  def post_batch(body, token: @token, headers: {})
    defaults = { "Content-Type" => "application/json" }
    defaults["Authorization"] = "Bearer #{token}" if token
    post api_v1_events_batch_path, params: body, headers: defaults.merge(headers)
  end

  def batch_json(*events) = { events: events.map { JSON.parse(it) } }.to_json

  def enqueue_notifications(&block)
    names = []
    callback = ->(name, *) { names << name }
    ActiveSupport::Notifications.subscribed(callback, /\Aenqueue(_all)?\.active_job\z/, &block)
    names
  end

  test "accepts a batch: 202, one encrypted InboundEvent per event, one bulk enqueue" do
    ids = %w[0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa1 0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0aa2]
    notifications = nil
    assert_difference(-> { InboundEvent.count }, 2) do
      notifications = enqueue_notifications { post_batch batch_json(event_json("full", event_id: ids[0]), minimal_json(event_id: ids[1])) }
    end

    assert_response :accepted
    assert_equal({ "accepted" => [ { "index" => 0, "id" => ids[0] }, { "index" => 1, "id" => ids[1] } ], "rejected" => [] },
                 response.parsed_body)
    assert_equal [ "enqueue_all.active_job" ], notifications
    stored = InboundEvent.where(event_uuid: ids).order(:id)
    assert_equal [ [ projects(:storefront).id, api_keys(:storefront_production).id, "production" ] ],
                 stored.map { [ it.project_id, it.api_key_id, it.environment ] }.uniq
    enqueued = enqueued_jobs.select { it[:job] == ProcessInboundEventJob }
    assert_equal [ "ingest" ], enqueued.map { it[:queue] }.uniq
    assert_equal stored.map(&:id), enqueued.map { ActiveJob::Arguments.deserialize(it[:args]).sole.id }.sort
  end

  test "stores each event on its own, encrypted, so processing is unchanged" do
    event = event_json("full")
    post_batch batch_json(event)
    inbound = InboundEvent.find_by!(event_uuid: response.parsed_body["accepted"].sole["id"])

    assert_equal JSON.parse(event), JSON.parse(inbound.body)
    raw = raw_column(InboundEvent, :body, inbound.id)
    %w[mara events NoMethodError].each { |text| assert_not_includes raw, text }

    perform_enqueued_jobs
    assert Occurrence.exists?(uuid: inbound.event_uuid)
  end

  test "accepts job sections in a batch" do
    post_batch batch_json(event_json("job"), minimal_json)
    assert_response :accepted
    ids = response.parsed_body["accepted"].map { it["id"] }

    perform_enqueued_jobs
    occurrences = ids.map { Occurrence.find_by!(uuid: it) }
    assert_equal [ "ChargeCustomerJob", nil ], occurrences.map { it.job["class"] }
    assert_equal "[FILTERED]", occurrences.first.job["arguments"][1]["card_token"]
  end

  test "job arguments and logs carry no payload content" do
    seen = []
    callback = ->(*, payload) { seen << payload[:params] }
    ActiveSupport::Notifications.subscribed(callback, "start_processing.action_controller") { post_batch batch_json(event_json("full")) }

    assert_equal({ "controller" => "api/v1/events/batches", "action" => "create" }, seen.sole.stringify_keys)
    serialized = enqueued_jobs.map { it[:args] }.to_json
    %w[mara NoMethodError hunter2].each { |text| assert_not_includes serialized, text }
  end

  test "partially accepts a batch, rejecting invalid events by index without echoing them" do
    post_batch({ events: [ JSON.parse(minimal_json), { exception: { message: "mara@example.com" } }, "mara@example.com",
                           JSON.parse(minimal_json) ] }.to_json)

    assert_response :accepted
    body = response.parsed_body
    assert_equal [ 0, 3 ], body["accepted"].map { it["index"] }
    assert_equal [ { "index" => 1, "error" => "invalid_payload", "messages" => [ "exception.class is required" ] },
                   { "index" => 2, "error" => "invalid_payload", "messages" => [ "event must be a JSON object" ] } ], body["rejected"]
    assert_not_includes response.body, "mara"
    assert_equal 2, enqueued_jobs.size
  end

  test "422 with the same shape when no event is accepted" do
    assert_no_difference(-> { InboundEvent.count }) { post_batch({ events: [ {}, [] ] }.to_json) }

    assert_response :unprocessable_content
    assert_equal({ "accepted" => [], "rejected" => [
      { "index" => 0, "error" => "invalid_payload", "messages" => [ "exception.class is required" ] },
      { "index" => 1, "error" => "invalid_payload", "messages" => [ "event must be a JSON object" ] } ] }, response.parsed_body)
    assert_no_enqueued_jobs
  end

  test "rejects an event that re-serialises over 512 KiB as payload_too_large" do
    huge = { exception: { class: "E", message: "x" * Ingest::Limits::BODY_BYTES } }
    post_batch({ events: [ huge, JSON.parse(minimal_json) ] }.to_json)

    assert_response :accepted
    assert_equal [ { "index" => 0, "error" => "payload_too_large" } ], response.parsed_body["rejected"]
    assert_equal [ 1 ], response.parsed_body["accepted"].map { it["index"] }
  end

  test "422 invalid_payload for a missing, non-array, empty or oversized events array" do
    { "{}" => "events must be an array", '{"events":{"a":1}}' => "events must be an array", "[]" => "body must be a JSON object",
      '{"events":[]}' => "events must not be empty",
      { events: Array.new(101) { JSON.parse(minimal_json) } }.to_json => "events must hold at most 100 events" }.each do |body, message|
      assert_no_difference(-> { InboundEvent.count }) { post_batch body }
      assert_response :unprocessable_content
      assert_equal({ "error" => "invalid_payload", "messages" => [ message ] }, response.parsed_body, body.first(40))
    end
  end

  test "duplicate event ids are accepted, stored and counted once by processing" do
    id = "0192f7a4-6c1e-7b3a-9d21-5f0c8e1b0dd9"
    post_batch batch_json(minimal_json(event_id: id), minimal_json(event_id: id))
    assert_response :accepted
    post_batch batch_json(minimal_json(event_id: id))
    assert_response :accepted

    assert_equal 3, InboundEvent.where(event_uuid: id).count
    perform_enqueued_jobs
    assert_equal 1, Occurrence.where(uuid: id).count
    assert_equal 0, InboundEvent.where(event_uuid: id).count
  end

  test "runs the same number of queries for 1 or 50 events" do
    counts = [ 1, 50 ].map do |size|
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { post_batch batch_json(*Array.new(size) { minimal_json }) }
      assert_response :accepted
      queries.size
    end

    assert_equal counts.first, counts.last
  end

  test "accepts an out-of-range number, stored as null like a single event" do
    post_batch '{"events":[{"exception":{"class":"E"},"context":{"big":1e400}}]}'
    assert_response :accepted

    inbound = InboundEvent.find_by!(event_uuid: response.parsed_body["accepted"].sole["id"])
    assert_equal({ "big" => nil }, JSON.parse(inbound.body)["context"])
  end

  test "accepts gzip bodies" do
    post_batch ActiveSupport::Gzip.compress(batch_json(minimal_json, minimal_json)), headers: { "Content-Encoding" => "gzip" }
    assert_response :accepted
    assert_equal 2, response.parsed_body["accepted"].size
  end

  test "records key usage and scopes events to the key" do
    api_keys(:storefront_staging).update_column(:last_used_at, nil)
    post_batch batch_json(minimal_json, minimal_json), token: FIXTURE_TOKENS[:storefront_staging]
    assert_not_nil api_keys(:storefront_staging).reload.last_used_at
    assert_equal [ "staging" ], InboundEvent.order(:id).last(2).map(&:environment).uniq
  end

  test "401 for missing or unknown keys, before content checks" do
    [ nil, "gs_live_unknown" ].each do |token|
      post_batch "nope", token:, headers: { "Content-Type" => "text/plain" }
      assert_response :unauthorized
      assert_equal({ "error" => "invalid_api_key" }, response.parsed_body)
      assert_equal 'Bearer realm="ingest"', response.headers["WWW-Authenticate"]
    end
  end

  test "415 for other content types and encodings" do
    post_batch batch_json(minimal_json), headers: { "Content-Type" => "text/plain" }
    assert_response :unsupported_media_type
    post_batch batch_json(minimal_json), headers: { "Content-Encoding" => "br" }
    assert_response :unsupported_media_type
    assert_equal({ "error" => "unsupported_media_type" }, response.parsed_body)
  end

  test "400 for malformed JSON or gzip, without echoing it" do
    [ [ '{"events":[{"user":"mara@example.com"}', {} ], [ "nope", { "Content-Encoding" => "gzip" } ] ].each do |body, headers|
      post_batch body, headers: headers
      assert_response :bad_request
      assert_equal({ "error" => "invalid_json" }, response.parsed_body)
    end
  end

  test "413 for bodies over 2 MiB, compressed or decompressed; bodies over 512 KiB up to 2 MiB are fine" do
    message = "x" * 400.kilobytes
    fits = { events: Array.new(4) { { exception: { class: "E", message: } } } }.to_json
    post_batch fits
    assert_response :accepted
    assert_operator fits.bytesize, :>, Ingest::Limits::BODY_BYTES

    big = { events: Array.new(6) { { exception: { class: "E", message: } } } }.to_json
    assert_no_difference(-> { InboundEvent.count }) { post_batch big }
    assert_response :content_too_large
    assert_equal({ "error" => "payload_too_large" }, response.parsed_body)

    post_batch ActiveSupport::Gzip.compress(big), headers: { "Content-Encoding" => "gzip" }
    assert_response :content_too_large
  end

  class RateLimitTest < ActionDispatch::IntegrationTest
    include IngestTestSupport

    setup do
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      @key_id = api_keys(:storefront_production).id
    end

    teardown { Rails.cache = @original_cache }

    def headers(token) = { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }

    def post_batch(count, token = FIXTURE_TOKENS[:storefront_production])
      post api_v1_events_batch_path, params: { events: Array.new(count) { JSON.parse(minimal_json) } }.to_json, headers: headers(token)
    end

    def post_event(token = FIXTURE_TOKENS[:storefront_production])
      post api_v1_events_path, params: minimal_json, headers: headers(token)
    end

    def counter(name, id) = Rails.cache.read("rate-limit:api/v1/events:#{name}:#{id}", raw: true).to_i

    def use_up(name, id, amount)
      Rails.cache.increment("rate-limit:api/v1/events:#{name}:#{id}", amount, expires_in: 1.minute)
    end

    test "a batch of N uses N of the key and account allowances that single events share" do
      post_batch 10
      post_event
      assert_response :accepted

      assert_equal 11, counter("key", @key_id)
      assert_equal 11, counter("account", accounts(:acme).id)
      assert_equal 2, counter("ip", "127.0.0.1"), "the IP limit counts requests"
    end

    test "429 for the whole batch when it would go over the key limit; nothing is stored or used up" do
      use_up "key", @key_id, Ingest::Limits::RATE_PER_KEY - 5

      assert_no_difference(-> { InboundEvent.count }) { post_batch 6 }
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
      assert_equal({ "error" => "rate_limited" }, response.parsed_body)
      assert_equal Ingest::Limits::RATE_PER_KEY - 5, counter("key", @key_id), "the unit taken before the body was read is given back"
      assert_equal 0, counter("account", accounts(:acme).id)

      post_batch 5
      assert_response :accepted
      post_event
      assert_response :too_many_requests, "single events share the counter"
    end

    test "batches from all of an account's keys count toward the account limit" do
      use_up "account", accounts(:acme).id, Ingest::Limits::RATE_PER_ACCOUNT - 3

      post_batch 4, FIXTURE_TOKENS[:storefront_staging]
      assert_response :too_many_requests
      assert_equal 0, counter("key", api_keys(:storefront_staging).id)
      post_batch 4, FIXTURE_TOKENS[:umbrella_production]
      assert_response :accepted, "other accounts are unaffected"
    end

    test "a refused body still uses one unit, like a single request, so malformed batches are not free" do
      post api_v1_events_batch_path, params: '{"events":"x"}', headers: headers(FIXTURE_TOKENS[:storefront_production])
      assert_response :unprocessable_content
      post api_v1_events_batch_path, params: "{nope", headers: headers(FIXTURE_TOKENS[:storefront_production])
      assert_response :bad_request

      assert_equal 2, counter("key", @key_id)
      assert_equal 2, counter("account", accounts(:acme).id)
    end

    test "an exhausted key is turned away before its body is read" do
      use_up "key", @key_id, Ingest::Limits::RATE_PER_KEY
      post api_v1_events_batch_path, params: "nope",
           headers: headers(FIXTURE_TOKENS[:storefront_production]).merge("Content-Type" => "text/plain")
      assert_response :too_many_requests
    end

    test "the IP limit is shared with the single endpoint and runs before authentication" do
      use_up "ip", "127.0.0.1", Ingest::Limits::RATE_PER_IP
      post_batch 1, "gs_live_unknown"
      assert_response :too_many_requests
    end

    test "429 quota_exceeded once the monthly quota is used up" do
      accounts(:acme).update!(monthly_event_quota: 1)

      assert_no_difference(-> { InboundEvent.count }) { post_batch 2 }
      assert_response :too_many_requests
      assert_equal({ "error" => "quota_exceeded" }, response.parsed_body)
    end
  end
end
