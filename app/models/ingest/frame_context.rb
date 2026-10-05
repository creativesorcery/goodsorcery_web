# Bounded, scrubbed source context and locals for a backtrace frame.
class Ingest::FrameContext
  def self.locals(value, scrubber:)
    return {} unless value.is_a?(Hash)

    bounded = value.first(Ingest::Limits::LOCALS).to_h do |name, local|
      [ Ingest::TreeLimiter.truncate(name, Ingest::Limits::KEY), Ingest::TreeLimiter.truncate(local, Ingest::Limits::LOCAL_VALUE) ]
    end
    scrubber.scrub(bounded)
  end

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
        @scrubber.scrub_text(Ingest::TreeLimiter.truncate(line, Ingest::Limits::CONTEXT_LINE))
      end
    end
end
