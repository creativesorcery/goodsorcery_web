# GET /api/v1/verify: confirms that an ingest key is valid and the endpoint is
# reachable (the goodsorcery gem's install check). Creates nothing and counts
# toward no ingest allowance or quota; it has its own modest limits.
class Api::V1::VerificationsController < ActionController::API
  include ApiKeyAuthentication
  include IngestErrorResponses

  rate_limit to: Ingest::Limits::RATE_PER_IP, within: Ingest::Limits::RATE_WINDOW, name: "ip",
             by: -> { request.remote_ip }, with: -> { render_rate_limited }, store: Ingest::RateLimitStore
  before_action :authenticate_api_key
  rate_limit to: Ingest::Limits::VERIFY_RATE_PER_KEY, within: Ingest::Limits::RATE_WINDOW, name: "key",
             by: -> { current_api_key.id }, with: -> { render_rate_limited }, store: Ingest::RateLimitStore

  def show
    render json: { ok: true, environment: current_api_key.environment }
  end
end
