# Raised when an ingest body exceeds Ingest::Limits::BODY_BYTES (compressed or not).
class Ingest::PayloadTooLarge < StandardError
  def initialize(message = "payload too large") = super
end
