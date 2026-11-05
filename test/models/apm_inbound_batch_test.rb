require "test_helper"
require_relative "ingest/ingest_test_support"

class ApmInboundBatchTest < ActiveSupport::TestCase
  include IngestTestSupport

  setup { @key = ApiKey::Credential.new(api_keys(:storefront_staging).id, projects(:storefront).id, "staging", accounts(:acme).id) }

  test "store inserts once per project, kind and uuid, with the body encrypted" do
    uuid = SecureRandom.uuid_v7
    id = ApmInboundBatch.store(@key, kind: "metrics", uuid:, body: '{"secret":"apm-fixture-secret"}')
    assert_kind_of Integer, id
    assert_nil ApmInboundBatch.store(@key, kind: "metrics", uuid:, body: "{}"), "a resent batch"
    assert ApmInboundBatch.store(@key, kind: "traces", uuid:, body: "{}"), "another kind"

    batch = ApmInboundBatch.find(id)
    assert_equal [ "staging", "metrics" ], [ batch.environment, batch.kind ]
    assert_equal '{"secret":"apm-fixture-secret"}', batch.body
    assert_not_includes raw_column(ApmInboundBatch, :body, id), "apm-fixture-secret"
  end

  test "the fixture body is ciphertext" do
    assert_not_includes raw_column(ApmInboundBatch, :body, apm_inbound_batches(:storefront_pending_metrics).id), "Checkouts"
  end
end
