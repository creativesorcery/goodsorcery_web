# JSON error responses of the ingest API ({"error":"<code>"}). They never
# echo anything from the request.
module IngestErrorResponses
  private
    def render_rate_limited
      response.headers["Retry-After"] = Ingest::Limits::RATE_WINDOW.to_i.to_s
      render_error "rate_limited", 429
    end

    def render_error(code, status)
      render json: { error: code }, status:
    end
end
