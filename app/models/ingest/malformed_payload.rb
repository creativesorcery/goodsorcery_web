# Raised while processing a stored inbound event that cannot be turned into an
# Ingest::Event. The message is fixed so no payload content leaks anywhere.
class Ingest::MalformedPayload < StandardError
  def initialize(message = "malformed payload") = super
end
