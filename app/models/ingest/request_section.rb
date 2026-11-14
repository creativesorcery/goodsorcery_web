# The request part of an event: summary fields plus the bounded, scrubbed
# params, headers and session trees.
class Ingest::RequestSection
  SUMMARY_FIELDS = %w[url method format request_id remote_ip].freeze

  def initialize(request, scrubber:)
    @request, @scrubber = request, scrubber
  end

  # { "url", "method", "format", "request_id", "remote_ip" } as scrubbed strings.
  def summary
    @request.slice(*SUMMARY_FIELDS).select { |_, value| value.is_a?(String) || value.is_a?(Numeric) }
      .transform_values { |value| @scrubber.scrub_text(value, limit: Ingest::Limits::STRING) }
  end

  def params = tree("params")

  def headers = tree("headers")

  def session = tree("session")

  private
    def tree(key)
      value = @request[key]
      value.is_a?(Hash) ? Ingest::TreeLimiter.new.limit(@scrubber.scrub(value)) : {}
    end
end
