# POST /api/v1/events: accepts one error event (docs/INGEST_API.md).
#
# The fast path only authenticates, bounds and validates the body, stores it
# encrypted as an InboundEvent and enqueues that record's GlobalID. The body
# never reaches params or logs (IngestBodyShield) and responses never echo it.
class Api::V1::EventsController < ActionController::API
  include ApiKeyAuthentication

  wrap_parameters false

  rate_limit to: Ingest::Limits::RATE_PER_IP, within: Ingest::Limits::RATE_WINDOW, name: "ip",
             by: -> { request.remote_ip }, with: -> { render_rate_limited }, store: Ingest::RateLimitStore
  before_action :authenticate_api_key
  rate_limit to: Ingest::Limits::RATE_PER_KEY, within: Ingest::Limits::RATE_WINDOW, name: "key",
             by: -> { current_api_key.id }, with: -> { render_rate_limited }, store: Ingest::RateLimitStore
  before_action :require_json

  rescue_from(Ingest::InvalidJson) { render_error "invalid_json", 400 }
  rescue_from(Ingest::PayloadTooLarge) { render_error "payload_too_large", 413 }

  def create
    body = request_body.read
    envelope = Ingest::Envelope.new(body)
    return render_invalid_payload(envelope) unless envelope.valid?

    inbound_event = store(body, envelope.event_uuid)
    ProcessInboundEventJob.perform_later(inbound_event)
    ApiKey.record_usage(current_api_key.id)
    render json: { id: inbound_event.event_uuid }, status: :accepted
  end

  private
    def request_body = @request_body ||= Ingest::RequestBody.new(request)

    def require_json
      return if request.media_type == "application/json" && request_body.supported_encoding?

      render_error "unsupported_media_type", 415
    end

    # One INSERT: the ids come from the authenticated key, so the belongs_to
    # presence validations (two extra SELECTs) are skipped on this hot path.
    def store(body, event_uuid)
      InboundEvent.new(project_id: current_api_key.project_id, api_key_id: current_api_key.id,
                       environment: current_api_key.environment, event_uuid:, body:, received_at: Time.current)
                  .tap { it.save!(validate: false) }
    end

    def render_invalid_payload(envelope)
      render json: { error: "invalid_payload", messages: envelope.errors }, status: 422
    end

    def render_rate_limited
      response.headers["Retry-After"] = Ingest::Limits::RATE_WINDOW.to_i.to_s
      render_error "rate_limited", 429
    end

    def render_error(code, status)
      render json: { error: code }, status:
    end
end
