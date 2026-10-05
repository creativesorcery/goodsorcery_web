require "test_helper"
require_relative "../models/ingest/ingest_test_support"

class ProcessInboundEventJobTest < ActiveJob::TestCase
  include IngestTestSupport

  test "processes the inbound event into an issue" do
    inbound = inbound_event_for(event_json)
    assert_difference -> { Occurrence.count }, 1 do
      ProcessInboundEventJob.perform_now(inbound)
    end
    assert_not InboundEvent.exists?(inbound.id)
  end

  test "runs on the ingest queue and serialises only a GlobalID" do
    inbound = inbound_event_for(event_json)
    job = ProcessInboundEventJob.new(inbound)
    assert_equal "ingest", job.queue_name
    assert_equal [ { "_aj_globalid" => inbound.to_global_id.to_s } ], job.serialize["arguments"]
  end

  test "an already processed event is discarded" do
    inbound = inbound_event_for(event_json)
    ProcessInboundEventJob.perform_later(inbound)
    inbound.delete
    assert_nothing_raised { perform_enqueued_jobs }
    assert_performed_jobs 1
  end

  test "database errors are re-raised without their details" do
    inbound = inbound_event_for(event_json)
    Occurrence.connection.execute("ALTER TABLE occurrences ADD CONSTRAINT ingest_test_reject CHECK (level = 'never') NOT VALID")
    error = assert_raises(Ingest::ProcessingFailed) { ProcessInboundEventJob.perform_now(inbound) }
    assert_equal "ActiveRecord::CheckViolation while processing inbound event #{inbound.id}", error.message
    assert_nil error.cause
    assert InboundEvent.exists?(inbound.id), "kept for a retry"
  end
end
