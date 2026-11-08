require "test_helper"
require_relative "../../../../models/apm/apm_test_support"
require_relative "../../../../models/ingest/ingest_test_support"

class Api::V1::Apm::MetricsControllerTest < ActionDispatch::IntegrationTest
  include ApmFixtureClock

  include ApmTestSupport
  include IngestTestSupport
  include ActiveJob::TestHelper

  setup { @token = FIXTURE_TOKENS[:storefront_production] }

  def post_metrics(body = metrics_body, token: @token, headers: {})
    defaults = { "Content-Type" => "application/json" }
    defaults["Authorization"] = "Bearer #{token}" if token
    post api_v1_apm_metrics_path, params: body, headers: defaults.merge(headers)
  end

  test "202 with the batch id; the body is stored encrypted and only its integer id is enqueued" do
    batch_id = SecureRandom.uuid_v7
    assert_difference -> { ApmInboundBatch.count }, 1 do
      post_metrics metrics_body(batch_id:)
    end

    assert_response :accepted
    assert_equal({ "id" => batch_id }, response.parsed_body)
    batch = ApmInboundBatch.order(:id).last
    assert_equal [ projects(:storefront).id, "production", "metrics", batch_id ], [ batch.project_id, batch.environment, batch.kind, batch.uuid ]
    assert_not_includes raw_column(ApmInboundBatch, :body, batch.id), "CheckoutsController"
    assert_enqueued_with(job: ProcessApmBatchJob, args: [ batch.id ], queue: "apm")
  end

  test "a resent batch_id is answered 202 but stored and enqueued once" do
    batch_id = SecureRandom.uuid_v7
    post_metrics metrics_body(batch_id:)
    assert_no_difference -> { ApmInboundBatch.count } do
      assert_no_enqueued_jobs(only: ProcessApmBatchJob) { post_metrics metrics_body(batch_id:) }
    end
    assert_response :accepted
    assert_equal batch_id, response.parsed_body["id"]
  end

  test "generates a batch id when the client sends none" do
    post_metrics metrics_body(batch_id: nil)
    assert_response :accepted
    assert Apm::TraceId.v7?(response.parsed_body["id"])
  end

  test "accepts gzip bodies" do
    post_metrics ActiveSupport::Gzip.compress(metrics_body), headers: { "Content-Encoding" => "gzip" }
    assert_response :accepted
  end

  test "the body never reaches params or the request log" do
    seen = []
    callback = ->(*, payload) { seen << payload[:params] }
    ActiveSupport::Notifications.subscribed(callback, "start_processing.action_controller") { post_metrics }
    assert_equal({ "controller" => "api/v1/apm/metrics", "action" => "create" }, seen.sole.stringify_keys)
  end

  test "an API key only ever writes to its own project and environment" do
    post_metrics metrics_body, token: FIXTURE_TOKENS[:umbrella_production]
    batch = ApmInboundBatch.order(:id).last
    assert_equal [ projects(:umbrella_app).id, "production" ], [ batch.project_id, batch.environment ]
  end

  test "401 for a missing or unknown key, before any content check" do
    post_metrics "nope", token: nil, headers: { "Content-Type" => "text/plain" }
    assert_response :unauthorized
    assert_equal({ "error" => "invalid_api_key" }, response.parsed_body)
    post_metrics metrics_body, token: "gs_live_unknown"
    assert_response :unauthorized
  end

  test "415, 400 and 413" do
    post_metrics metrics_body, headers: { "Content-Type" => "text/plain" }
    assert_response :unsupported_media_type
    post_metrics metrics_body, headers: { "Content-Encoding" => "br" }
    assert_response :unsupported_media_type
    post_metrics '{"minutes":'
    assert_equal [ 400, { "error" => "invalid_json" } ], [ response.status, response.parsed_body ]
    big = metrics_body(minutes: [ { minute: "2026-11-04T14:32:00Z", transactions: [ metrics_transaction(name: "x" * Apm::Limits::METRICS_BODY_BYTES) ] } ])
    post_metrics big
    assert_equal [ 413, { "error" => "payload_too_large" } ], [ response.status, response.parsed_body ]
    post_metrics ActiveSupport::Gzip.compress(big), headers: { "Content-Encoding" => "gzip" }
    assert_response :content_too_large
  end

  test "422 for the wrong shape stores nothing and names fields only" do
    assert_no_difference -> { ApmInboundBatch.count } do
      post_metrics metrics_body([ metrics_transaction(name: "mara@example.com").merge(count: 9) ])
    end
    assert_response :unprocessable_content
    assert_equal({ "error" => "invalid_payload", "messages" => [ "minutes[0].transactions[0].buckets must add up to count" ] },
                 response.parsed_body)
  end

  test "accepted when the account is over its monthly event quota" do
    accounts(:acme).update_entitlements!("monthly_event_quota" => 1)
    Rails.cache.write(Account.over_quota_key(accounts(:acme).id), true)
    with_hosted_mode { post_metrics }
    assert_response :accepted
  end

  class RateLimitTest < ActionDispatch::IntegrationTest
    include ApmTestSupport

    setup do
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown { Rails.cache = @original_cache }

    def post_metrics(token = FIXTURE_TOKENS[:storefront_production])
      post api_v1_apm_metrics_path, params: metrics_body,
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    end

    test "429 once a key exceeds 600 requests a minute; other keys are unaffected" do
      key_id = api_keys(:storefront_production).id
      Rails.cache.increment("rate-limit:api/v1/apm:key:#{key_id}", Apm::Limits::RATE_PER_KEY, expires_in: 1.minute)

      assert_no_difference(-> { ApmInboundBatch.count }) { post_metrics }
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
      assert_equal({ "error" => "rate_limited" }, response.parsed_body)
      post_metrics FIXTURE_TOKENS[:storefront_staging]
      assert_response :accepted
    end

    test "429 once an account or an IP exceeds its limit" do
      Rails.cache.increment("rate-limit:api/v1/apm:account:#{accounts(:acme).id}", Apm::Limits::RATE_PER_ACCOUNT, expires_in: 1.minute)
      post_metrics FIXTURE_TOKENS[:storefront_staging]
      assert_response :too_many_requests
      post_metrics FIXTURE_TOKENS[:umbrella_production]
      assert_response :accepted

      Rails.cache.increment("rate-limit:api/v1/apm:ip:127.0.0.1", Apm::Limits::RATE_PER_IP, expires_in: 1.minute)
      post_metrics FIXTURE_TOKENS[:umbrella_production]
      assert_response :too_many_requests
    end

    test "the counters are separate from error ingest" do
      key_id = api_keys(:storefront_production).id
      Rails.cache.increment("rate-limit:api/v1/events:key:#{key_id}", Ingest::Limits::RATE_PER_KEY, expires_in: 1.minute)
      Rails.cache.increment("rate-limit:api/v1/events:ip:127.0.0.1", Ingest::Limits::RATE_PER_IP, expires_in: 1.minute)

      2.times { post_metrics }
      assert_response :accepted
      assert_equal 2, Rails.cache.read("rate-limit:api/v1/apm:key:#{key_id}", raw: true).to_i
      assert_equal Ingest::Limits::RATE_PER_KEY, Rails.cache.read("rate-limit:api/v1/events:key:#{key_id}", raw: true).to_i
    end
  end
end
