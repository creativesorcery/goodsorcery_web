# Raised when an ingest body is not parseable JSON (or not decodable gzip/UTF-8).
# The message is fixed: parser messages can quote payload bytes and must never
# reach logs, Redis or error reports.
class Ingest::InvalidJson < StandardError
  def initialize(message = "invalid json") = super
end
