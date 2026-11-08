# An occurrence's backtrace for a tool result: app frames first (in call
# order), then framework and gem frames, at most MAX_FRAMES. The first
# CODE_FRAMES app frames carry their code context (±3 lines, as on the issue
# page); locals only when the token has the request_data scope.
#
#   summary = Mcp::BacktraceSummary.new(occurrence.frames, locals: false)
#   summary.frames      # => [{ file:, line:, method:, in_app:, code: [...] }, …]
#   summary.text_lines  # => ["→ app/services/cart_total.rb:42 in line_total", "    41 | …", …]
class Mcp::BacktraceSummary
  MAX_FRAMES = 30
  CODE_FRAMES = 5
  CODE_LINE = 200

  def initialize(frames, locals: false)
    @frames = Array(frames).map { |frame| Backtrace::Frame.from_payload(frame) }
    @locals = locals
  end

  def total = @frames.size

  def frames = @presented ||= ordered.each_with_index.map { |frame, index| present(frame, index) }

  def text_lines
    frames.flat_map { |frame| [ frame_line(frame), *code_text(frame) ] } + omitted_line
  end

  private
    def ordered = @frames.partition(&:app?).flatten.first(MAX_FRAMES)

    def present(frame, index)
      {
        file: Mcp::Captured.string(frame.file), line: frame.line, method: Mcp::Captured.string(frame.method_name, 120),
        in_app: frame.app?, gem: frame.gem_name, code: (code(frame) if frame.app? && index < CODE_FRAMES),
        locals: (Mcp::Captured.trim(frame.locals) if @locals && frame.app? && frame.locals?)
      }.compact
    end

    def code(frame)
      frame.code_lines.map { |number, text, error| { line: number, text: Mcp::Captured.string(text, CODE_LINE), error: } }
    end

    def frame_line(frame)
      location = [ frame[:file], frame[:line] ].compact.join(":")
      "#{frame[:in_app] ? '→' : ' '} #{location} in #{frame[:method]}#{" (#{frame[:gem]})" if frame[:gem]}"
    end

    def code_text(frame)
      Array(frame[:code]).map { |code| "    #{code[:error] ? '>' : ' '}#{code[:line].to_s.rjust(5)} | #{code[:text]}" }
    end

    def omitted_line
      total > MAX_FRAMES ? [ "  … #{total - MAX_FRAMES} more frames" ] : []
    end
end
