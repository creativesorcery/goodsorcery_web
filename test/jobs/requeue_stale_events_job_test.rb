require "test_helper"

class RequeueStaleEventsJobTest < ActiveJob::TestCase
  test "re-enqueues stale inbound events" do
    stale = inbound_events(:storefront_pending)
    stale.update_column(:received_at, 11.minutes.ago)

    RequeueStaleEventsJob.perform_now

    assert_enqueued_with(job: ProcessInboundEventJob, args: [ stale ])
  end
end
