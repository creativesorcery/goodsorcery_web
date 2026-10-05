# Bearer-token authentication for the ingest API. The key lookup is a cached
# SHA-256 digest match (ApiKey.authenticate) that yields only ids and the
# environment, never the token itself.
module ApiKeyAuthentication
  extend ActiveSupport::Concern

  BEARER = /\ABearer[ \t]+([^\s]+)[ \t]*\z/i

  included do
    attr_reader :current_api_key
  end

  private
    def authenticate_api_key
      @current_api_key = ApiKey.authenticate(bearer_token)
      render_invalid_api_key unless current_api_key
    end

    def bearer_token
      request.authorization.to_s[BEARER, 1]
    end

    def render_invalid_api_key
      response.headers["WWW-Authenticate"] = 'Bearer realm="ingest"'
      render json: { error: "invalid_api_key" }, status: :unauthorized
    end
end
