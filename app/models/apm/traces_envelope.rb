# Request-time validation of a traces payload (docs/INGEST_API.md › Traces
# payload): 1 to 50 traces, each with the required fields well-typed. Spans
# are not judged here: Apm::TraceNormalizer drops malformed or unknown spans
# and keys when the batch is processed. Error messages never echo content.
class Apm::TracesEnvelope
  include Apm::JsonShape

  def initialize(body)
    @data = Ingest::Envelope.parse(body)
  end

  def valid? = errors.empty?

  def errors
    @errors ||= Apm::ShapeErrors.new.tap { check_body(it) }.to_a
  end

  def batch_uuid
    @batch_uuid ||= Apm::TraceId.uuid(@data.is_a?(Hash) ? @data["batch_id"] : nil) || SecureRandom.uuid_v7
  end

  private
    def check_body(errors)
      return errors.add("body must be a JSON object") unless @data.is_a?(Hash)

      traces = @data["traces"]
      sizes = Apm::Limits::TRACES
      return errors.add("traces must be an array of #{sizes.min} to #{sizes.max} entries") unless list?(traces, sizes)

      traces.each_with_index do |trace, index|
        Apm::TracesEnvelope::TraceCheck.new(trace, "traces[#{index}]").check(errors)
      end
    end
end
