# An occurrence's backtrace, arranged app-first for the issue page: each app
# frame stands on its own, and runs of consecutive framework/library frames fold
# into one segment ("3 framework frames hidden (activesupport, activerecord)").
#
#   backtrace = Backtrace.new(occurrence.frames, exception_class: "NoMethodError", message: occurrence.exception_message)
#   backtrace.segments  # => [Segment(app, top), Segment(framework × 2), Segment(app), …]
#   backtrace.raw       # => "NoMethodError: …\n  app/services/cart_total.rb:42 in line_total\n…"
#
# Frames come from the decrypted payload: never cache or log anything built here.
class Backtrace
  CONTEXT_RADIUS = 3
  PACKAGE_PATH = %r{(?:\A|/)(?:gems|crates)/([^/]+?)-\d[^/]*/}

  # One frame of the stored payload (docs/ARCHITECTURE.md §3.3). Payloads
  # stored before protocol revision 1.1 call the package "gem".
  Frame = Data.define(:file, :line, :column, :method_name, :module_name, :in_app, :package,
                      :context_start, :context_lines, :locals) do
    def self.from_payload(hash)
      context = hash["context"].is_a?(Hash) ? hash["context"] : {}
      new(file: hash["file"].to_s, line: hash["line"]&.to_i, column: hash["column"]&.to_i, method_name: hash["method"].to_s,
        module_name: hash["module"].presence, in_app: hash["in_app"] == true, package: package(hash),
        context_start: context["start_line"].to_i, context_lines: Array(context["lines"]).map(&:to_s),
        locals: hash["locals"].is_a?(Hash) ? hash["locals"] : {})
    end

    def self.package(hash) = hash["package"].presence || hash["gem"].presence || hash["file"].to_s[PACKAGE_PATH, 1]

    def app? = in_app

    # "src/cart.rs:42:17", "app/models/order.rb:112", or the file alone.
    def location = [ file, line, (column if line) ].compact.join(":")

    # The module, unless the method name already starts with it.
    def module_label = (module_name unless module_name.nil? || method_name.start_with?(module_name))

    # "src/cart.rs:42:17 in cart::total" for the Raw view.
    def to_s = [ location, ("in #{[ module_label, method_name.presence ].compact.join(' ')}" if method_name.present?) ].compact.join(" ")

    # [[line number, text, error line?]] within ±CONTEXT_RADIUS of the error line.
    def code_lines
      numbered = context_lines.each_with_index.map { |text, index| [ context_start + index, text ] }
      numbered.select { |number, _| near_error_line?(number) }.map { |number, text| [ number, text, number == line ] }
    end

    def code? = code_lines.any?

    def locals? = locals.any?

    private
      def near_error_line?(number)
        line.nil? || (number - line).abs <= CONTEXT_RADIUS
      end
  end

  attr_reader :frames

  def initialize(frames, exception_class:, message: "")
    @frames = Array(frames).map { |frame| Frame.from_payload(frame) }
    @exception_class = exception_class
    @message = message
  end

  def segments
    @segments ||= frames.slice_when { |a, b| a.app? || b.app? }.map { |run| Segment.new(run) }
      .tap { |list| list.find(&:app?)&.expand! }
  end

  def top_app_frame = frames.find(&:app?)

  def app_frames? = top_app_frame.present?

  def framework_frame_count = frames.count { |frame| !frame.app? }

  def empty? = frames.empty?

  # Plain-text trace for the Raw view and Copy, one "file:line in method" per frame.
  def raw
    [ "#{@exception_class}: #{@message}", *frames.map { |frame| "  #{frame}" } ].join("\n")
  end
end
