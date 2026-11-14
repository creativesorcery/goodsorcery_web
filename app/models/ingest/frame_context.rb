# Bounded, scrubbed source context and locals for a backtrace frame.
class Ingest::FrameContext
  # Scrubbed while still structured, so keys nested in a hash local are
  # filtered too; only then turned into bounded strings.
  def self.locals(value, scrubber:)
    return {} unless value.is_a?(Hash)

    scrubbed = Ingest::TreeLimiter.new.limit(scrubber.scrub(value.first(Ingest::Limits::LOCALS).to_h))
    scrubbed.to_h { |name, local| [ name, Ingest::TreeLimiter.truncate(local_text(local), Ingest::Limits::LOCAL_VALUE) ] }
  end

  def self.local_text(local) = local.is_a?(Hash) || local.is_a?(Array) ? local.to_json : local.to_s

  def initialize(value, scrubber:)
    @value = value.is_a?(Hash) ? value : {}
    @scrubber = scrubber
  end

  # { start_line:, lines: [...] } or {} when no usable lines were sent.
  def to_h
    lines.any? ? { start_line:, lines: } : {}
  end

  private
    def start_line
      line = @value["start_line"]
      line.is_a?(Integer) && line.positive? ? line : 1
    end

    def lines
      @lines ||= Array(@value["lines"]).first(Ingest::Limits::CONTEXT_LINES).map do |line|
        @scrubber.scrub_text(line, limit: Ingest::Limits::CONTEXT_LINE)
      end
    end
end
