# The request checks of the performance ingest endpoints
# (docs/ARCHITECTURE.md §13.3), in the documented order: per-IP rate limit,
# API key (401), per-key and per-account request limits (429), media type
# (415), then, while the action reads the body, size (413), JSON (400) and
# shape (422). There is no quota check: performance data never counts toward
# the event quota. Every counter lives in its own scope
# (Apm::Limits::RATE_SCOPE), apart from the error-event counters, and each
# request takes one unit.
#
# Accepted bodies are stored encrypted as an ApmInboundBatch and only its
# integer id is enqueued. Bodies never reach params or logs
# (IngestBodyShield) and responses never echo them.
module ApmIngestEndpoint
  extend ActiveSupport::Concern
  include ApiKeyAuthentication
  include IngestErrorResponses

  included do
    wrap_parameters false

    rate_limit to: Apm::Limits::RATE_PER_IP, within: Apm::Limits::RATE_WINDOW, name: "ip",
               scope: Apm::Limits::RATE_SCOPE, by: -> { request.remote_ip }, with: -> { render_rate_limited },
               store: Ingest::RateLimitStore
    before_action :authenticate_api_key
    before_action :limit_request_rate
    before_action :require_json

    rescue_from(Ingest::InvalidJson) { render_error "invalid_json", 400 }
    rescue_from(Ingest::PayloadTooLarge) { render_error "payload_too_large", 413 }
  end

  private
    # Validates the whole body, stores it once per batch_id and enqueues it.
    # A resent batch is answered like a new one but stored and counted once.
    def accept_batch(envelope_class, kind:, max:)
      body = Ingest::RequestBody.new(request, max:).read
      envelope = envelope_class.new(body)
      return render_invalid_payload(envelope.errors) unless envelope.valid?

      id = ApmInboundBatch.store(current_api_key, kind:, uuid: envelope.batch_uuid, body:)
      ProcessApmBatchJob.perform_later(id) if id
      ApiKey.record_usage(current_api_key.id)
      render json: { id: envelope.batch_uuid }, status: :accepted
    end

    def limit_request_rate
      limit = Ingest::EventRateLimit.new(current_api_key, scope: Apm::Limits::RATE_SCOPE,
                                         per_key: Apm::Limits::RATE_PER_KEY, per_account: Apm::Limits::RATE_PER_ACCOUNT)
      render_rate_limited unless limit.admit?(1)
    end

    def require_json
      return if request.media_type == "application/json" && Ingest::RequestBody.new(request).supported_encoding?

      render_error "unsupported_media_type", 415
    end

    def render_invalid_payload(messages)
      render json: { error: "invalid_payload", messages: }, status: 422
    end
end
