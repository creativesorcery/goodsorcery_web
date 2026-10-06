# The request checks shared by the ingest endpoints (docs/INGEST_API.md), in
# the documented order: per-IP rate limit, API key (401), per-key and
# per-account event limits, monthly quota, media type (415), then, while the
# action reads the body, size (413) and JSON (400).
#
# The per-IP counter counts requests and is shared by every ingest endpoint
# (one scope). The key and account counters count events through
# Ingest::EventRateLimit: every request takes one unit before its body is
# read, and the batch endpoint takes the rest once it knows its event count.
# Bodies never reach params or logs (IngestBodyShield) and responses never
# echo them.
module IngestEndpoint
  extend ActiveSupport::Concern
  include ApiKeyAuthentication
  include IngestErrorResponses

  included do
    wrap_parameters false

    rate_limit to: Ingest::Limits::RATE_PER_IP, within: Ingest::Limits::RATE_WINDOW, name: "ip",
               scope: Ingest::RateCounter::SCOPE, by: -> { request.remote_ip }, with: -> { render_rate_limited },
               store: Ingest::RateLimitStore
    before_action :authenticate_api_key
    before_action :limit_event_rate
    before_action :enforce_quota
    before_action :require_json

    rescue_from(Ingest::InvalidJson) { render_error "invalid_json", 400 }
    rescue_from(Ingest::PayloadTooLarge) { render_error "payload_too_large", 413 }
  end

  private
    def request_body = @request_body ||= Ingest::RequestBody.new(request, max: max_body_bytes)

    def max_body_bytes = Ingest::Limits::BODY_BYTES

    def event_rate_limit = @event_rate_limit ||= Ingest::EventRateLimit.new(current_api_key)

    # One unit of the key and account allowances, before the body is read.
    def limit_event_rate
      render_rate_limited unless event_rate_limit.admit?(1)
    end

    def enforce_quota
      render_error "quota_exceeded", 429 if Account.over_quota?(current_api_key.account_id)
    end

    def require_json
      return if request.media_type == "application/json" && request_body.supported_encoding?

      render_error "unsupported_media_type", 415
    end

    # Stores the [event_uuid, body] pairs and enqueues them with one bulk push.
    def store_and_enqueue(events)
      inbound_events = InboundEvent.store_for(current_api_key, events)
      ActiveJob.perform_all_later(inbound_events.map { ProcessInboundEventJob.new(it) })
      ApiKey.record_usage(current_api_key.id)
    end

    def render_invalid_payload(messages)
      render json: { error: "invalid_payload", messages: }, status: 422
    end
end
