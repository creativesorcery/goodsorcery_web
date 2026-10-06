# POST /api/v1/events/batch: accepts up to Ingest::Limits::BATCH_EVENTS error
# events in one request (docs/INGEST_API.md › Batches).
#
# Each event is validated and re-serialised on its own and stored as its own
# encrypted InboundEvent (one multi-row INSERT), so processing is identical to
# the single endpoint. Invalid events are rejected by index; the rest are
# accepted. The key and account allowances are charged one unit per event
# once the event count is known (after the body is parsed).
class Api::V1::Events::BatchesController < ActionController::API
  include IngestEndpoint

  def create
    batch = Ingest::Batch.new(request_body.read)
    return render_invalid_payload(batch.errors) unless batch.valid?
    return render_rate_limited unless event_rate_limit.admit?(batch.size)

    accepted = batch.accepted_items
    store_and_enqueue(accepted.map { [ it.event_uuid, it.body ] }) if accepted.any?
    render json: { accepted: accepted.map(&:acceptance), rejected: batch.rejected_items.map(&:rejection) },
           status: accepted.any? ? :accepted : :unprocessable_content
  end

  private
    def max_body_bytes = Ingest::Limits::BATCH_BODY_BYTES

    # The event count is unknown until the body is parsed, so this early check
    # only turns away a key or account with no room left at all; #create
    # charges the full count.
    def limit_event_rate
      render_rate_limited if event_rate_limit.exhausted?
    end
end
