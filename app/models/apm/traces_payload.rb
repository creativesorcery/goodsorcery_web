# Reads a stored, already validated traces body (Apm::TracesEnvelope) into
# normalised traces (Apm::TraceNormalizer::Result), skipping traces whose
# minute is more than 2 hours old or more than 2 minutes ahead.
class Apm::TracesPayload
  def initialize(body, normalizer: Apm::TraceNormalizer.new)
    @data = JSON.parse(body)
    @normalizer = normalizer
  end

  def traces(now: Time.current)
    window = (now - Apm::Limits::TRACES_PAST)..(now + Apm::Limits::FUTURE)
    @data.fetch("traces").select { window.cover?(Apm::JsonShape.minute(it["minute"])) }.map { @normalizer.normalize(it) }
  end
end
