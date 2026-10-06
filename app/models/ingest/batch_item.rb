# One event of a batch, validated like a single request body. It is stored on
# its own, re-serialised, so the processor never sees the batch wrapper; the
# re-serialised event must fit Ingest::Limits::BODY_BYTES.
class Ingest::BatchItem
  # The parser turns an out-of-range number (1e400) into Infinity, which plain
  # JSON.generate refuses. The block only ever sees such floats (everything
  # else came from JSON) and writes them as null, as processing of a single
  # event would.
  ENCODER = JSON::Coder.new { |value| value.is_a?(Float) ? nil : value.to_s }

  attr_reader :index

  def initialize(data, index)
    @data = data
    @index = index
    @envelope = Ingest::Envelope.new(data:, subject: "event")
  end

  def rejected? = rejection.present?

  # { index:, error:, messages: } for an event that is not stored, else nil.
  def rejection
    return { index:, error: "invalid_payload", messages: @envelope.errors } unless @envelope.valid?

    { index:, error: "payload_too_large" } if body.bytesize > Ingest::Limits::BODY_BYTES
  end

  def acceptance = { index:, id: event_uuid }

  def event_uuid = @envelope.event_uuid

  def body
    @body ||= ENCODER.dump(@data)
  end
end
