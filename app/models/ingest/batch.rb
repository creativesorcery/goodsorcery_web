# Request-time validation of a batch body: {"events":[…]} holding 1 to
# Ingest::Limits::BATCH_EVENTS events. Each event is judged on its own by an
# Ingest::BatchItem. Error messages never echo payload content.
class Ingest::Batch
  def initialize(body)
    @data = Ingest::Envelope.parse(body)
  end

  def valid? = errors.empty?

  def errors
    @errors ||= [ shape_error ].compact
  end

  def size = events.size

  def items
    @items ||= events.each_with_index.map { |event, index| Ingest::BatchItem.new(event, index) }
  end

  def accepted_items = items.reject(&:rejected?)

  def rejected_items = items.select(&:rejected?)

  private
    def events = @data.is_a?(Hash) ? @data["events"] : nil

    def shape_error
      return "body must be a JSON object" unless @data.is_a?(Hash)
      return "events must be an array" unless events.is_a?(Array)
      return "events must not be empty" if events.empty?

      "events must hold at most #{Ingest::Limits::BATCH_EVENTS} events" if events.size > Ingest::Limits::BATCH_EVENTS
    end
end
