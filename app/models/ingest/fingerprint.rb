# Grouping key for an event: SHA-256 hex of its parts joined by "\x1F".
#   1. a client fingerprint            → ["custom", *parts]
#   2. a top in-app frame              → ["v1", class, file, method] (no line numbers)
#   3. otherwise                       → ["v1", class, redacted message]
class Ingest::Fingerprint
  SEPARATOR = "\x1F".freeze

  def initialize(exception_class:, top_app_frame:, redacted_message:, client_parts: nil)
    @exception_class = exception_class
    @top_app_frame = top_app_frame
    @redacted_message = redacted_message
    @client_parts = self.class.client_parts(client_parts)
  end

  # Up to 10 scalar parts of at most 200 chars each, or [] when none were sent.
  def self.client_parts(value)
    parts = Array(value).select { |part| part.is_a?(String) || part.is_a?(Numeric) }
    parts.first(Ingest::Limits::FINGERPRINT_PARTS).map { |part| part.to_s.first(Ingest::Limits::FINGERPRINT_PART) }
  end

  def digest
    Digest::SHA256.hexdigest(parts.join(SEPARATOR))
  end

  def parts
    return [ "custom", *@client_parts ] if @client_parts.any?
    return [ "v1", @exception_class, @top_app_frame.file, @top_app_frame.method_name.to_s ] if @top_app_frame

    [ "v1", @exception_class, @redacted_message ]
  end
end
