# Request-time validation of an ingest body: one JSON object with a non-empty
# `exception.class` string. Error messages never echo payload content.
class Ingest::Envelope
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  def initialize(body)
    @data = parse(body)
  end

  def valid? = errors.empty?

  def errors
    @errors ||= [ shape_error ].compact
  end

  # The client's event_id when it is a UUID, otherwise a fresh UUIDv7.
  def event_uuid
    @event_uuid ||= client_event_id || SecureRandom.uuid_v7
  end

  private
    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError, EncodingError
      raise Ingest::InvalidJson, cause: nil
    end

    def shape_error
      return "body must be a JSON object" unless @data.is_a?(Hash)

      "exception.class is required" unless exception_class.is_a?(String) && exception_class.strip.present?
    end

    def exception_class
      exception = @data["exception"]
      exception["class"] if exception.is_a?(Hash)
    end

    def client_event_id
      id = @data["event_id"]
      id.downcase if id.is_a?(String) && id.match?(UUID)
    end
end
