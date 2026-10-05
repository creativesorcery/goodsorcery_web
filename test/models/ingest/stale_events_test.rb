require "test_helper"

class Ingest::StaleEventsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "re-enqueues only inbound events older than ten minutes" do
    stale = inbound_events(:storefront_pending)
    stale.update_column(:received_at, 11.minutes.ago)
    fresh = stale.dup.tap { it.update!(received_at: Time.current, event_uuid: SecureRandom.uuid_v7, body: "{}") }

    assert_equal 1, Ingest::StaleEvents.new.requeue
    assert_enqueued_with(job: ProcessInboundEventJob, args: [ stale ])
    assert_enqueued_jobs 1
    assert fresh.persisted?
  end
end
