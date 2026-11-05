require "test_helper"
require_relative "../../../../models/apm/apm_test_support"
require_relative "../../../../models/ingest/ingest_test_support"

class Api::V1::Apm::TracesControllerTest < ActionDispatch::IntegrationTest
  include ApmTestSupport
  include IngestTestSupport
  include ActiveJob::TestHelper

  def post_traces(body = traces_body, token: FIXTURE_TOKENS[:storefront_production], headers: {})
    defaults = { "Content-Type" => "application/json" }
    defaults["Authorization"] = "Bearer #{token}" if token
    post api_v1_apm_traces_path, params: body, headers: defaults.merge(headers)
  end

  test "202; stored encrypted as a traces batch and enqueued by integer id" do
    batch_id = SecureRandom.uuid_v7
    post_traces traces_body(batch_id:)

    assert_response :accepted
    assert_equal({ "id" => batch_id }, response.parsed_body)
    batch = ApmInboundBatch.order(:id).last
    assert_equal "traces", batch.kind
    %w[taxjar products checkout hunter2].each { assert_not_includes raw_column(ApmInboundBatch, :body, batch.id), it }
    assert_enqueued_with(job: ProcessApmBatchJob, args: [ batch.id ])
  end

  test "the same batch_id may be used once per kind" do
    batch_id = SecureRandom.uuid_v7
    post_traces traces_body(batch_id:)
    post api_v1_apm_metrics_path, params: metrics_body(batch_id:),
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{FIXTURE_TOKENS[:storefront_production]}" }
    assert_equal 2, ApmInboundBatch.where(uuid: batch_id).count
  end

  test "the body never reaches params or the request log" do
    seen = []
    callback = ->(*, payload) { seen << payload[:params] }
    ActiveSupport::Notifications.subscribed(callback, "start_processing.action_controller") { post_traces }
    assert_equal({ "controller" => "api/v1/apm/traces", "action" => "create" }, seen.sole.stringify_keys)
  end

  test "gzip, 401, 415, 400, 413 and 422" do
    post_traces ActiveSupport::Gzip.compress(traces_body), headers: { "Content-Encoding" => "gzip" }
    assert_response :accepted
    post_traces token: nil
    assert_response :unauthorized
    post_traces headers: { "Content-Type" => "text/plain" }
    assert_response :unsupported_media_type
    post_traces "{"
    assert_response :bad_request
    post_traces traces_body([ trace_hash(host: "x" * Apm::Limits::TRACES_BODY_BYTES) ])
    assert_response :content_too_large
    post_traces traces_body([])
    assert_equal [ 422, [ "traces must be an array of 1 to 50 entries" ] ], [ response.status, response.parsed_body["messages"] ]
  end

  test "traces up to 2 MiB are accepted" do
    post_traces traces_body([ trace_hash(host: "x" * 600.kilobytes) ])
    assert_response :accepted
  end
end
