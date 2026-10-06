# POST /api/v1/events: accepts one error event (docs/INGEST_API.md).
#
# The fast path only authenticates, bounds and validates the body, stores it
# encrypted as an InboundEvent and enqueues that record's GlobalID. The shared
# checks live in IngestEndpoint.
class Api::V1::EventsController < ActionController::API
  include IngestEndpoint

  def create
    body = request_body.read
    envelope = Ingest::Envelope.new(body)
    return render_invalid_payload(envelope.errors) unless envelope.valid?

    store_and_enqueue([ [ envelope.event_uuid, body ] ])
    render json: { id: envelope.event_uuid }, status: :accepted
  end

  private
    # One event: one unit of the key and account allowances.
    def limit_event_rate
      render_rate_limited unless event_rate_limit.admit?(1)
    end
end
