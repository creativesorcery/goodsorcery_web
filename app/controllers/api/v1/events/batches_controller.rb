# POST /api/v1/events/batch: accepts up to Ingest::Limits::BATCH_EVENTS error
# events in one request (docs/INGEST_API.md › Batches).
#
# Each event is validated and re-serialised on its own and stored as its own
# encrypted InboundEvent (one multi-row INSERT), so processing is identical to
# the single endpoint. Invalid events are rejected by index; the rest are
# accepted. The key and account allowances are charged one unit per event:
# one before the body is read, the rest once the event count is known.
class Api::V1::Events::BatchesController < ActionController::API
  include IngestEndpoint

  def create
    batch = Ingest::Batch.new(request_body.read)
    return render_invalid_payload(batch.errors) unless batch.valid?
    return render_rate_limited unless admit_rest_of?(batch)

    accepted = batch.accepted_items
    store_and_enqueue(accepted.map { [ it.event_uuid, it.body ] }) if accepted.any?
    render json: { accepted: accepted.map(&:acceptance), rejected: batch.rejected_items.map(&:rejection) },
           status: accepted.any? ? :accepted : :unprocessable_content
  end

  private
    def max_body_bytes = Ingest::Limits::BATCH_BODY_BYTES

    # IngestEndpoint#limit_event_rate took one unit before the body was read
    # (so a malformed 2 MiB body is not free to send); these are the other
    # N - 1. A batch that does not fit gives back the first unit too: a
    # request refused with 429 uses up nothing.
    def admit_rest_of?(batch)
      return true if event_rate_limit.admit?(batch.size - 1)

      event_rate_limit.give_back(1)
      false
    end
end
