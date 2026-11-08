# Bearer-token authentication for the MCP endpoint (docs/ARCHITECTURE.md
# §14.2). PersonalAccessToken.authenticate checks the digest, revocation,
# expiry and the user's membership of the token's account on every request
# (one query, never cached). Every failure gets the same 401: the response
# never says which check failed.
module PersonalAccessTokenAuthentication
  extend ActiveSupport::Concern
  include JsonRpcErrorResponses

  BEARER = ApiKeyAuthentication::BEARER

  included do
    attr_reader :current_personal_access_token
  end

  private
    def authenticate_personal_access_token
      @current_personal_access_token = PersonalAccessToken.authenticate(request.authorization.to_s[BEARER, 1])
      render_invalid_token unless current_personal_access_token
    end

    def render_invalid_token
      response.headers["WWW-Authenticate"] = 'Bearer realm="goodsorcery"'
      render_json_rpc_error :unauthorized, -32001, "invalid token"
    end
end
