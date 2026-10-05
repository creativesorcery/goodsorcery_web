# One normalised backtrace frame. Paths are normalised, code context and
# locals are bounded and scrubbed. `to_h` is the stored payload shape (§3.3).
class Ingest::Frame < Data.define(:file, :line, :method_name, :in_app, :gem_name, :context, :locals)
  APP_PATH = %r{\A(?:app|lib|config)/}
  VENDORED = %r{/gems/|vendor/bundle}
  GEM_DIR = %r{(?:\A|/)gems/([^/]+?)-(?:\d|\h{7,})[^/]*/}
  GEM_LIB = %r{(?:\A|/)([A-Za-z][\w.-]*?)-\d[\w.]*/lib/}

  class << self
    def from_hash(hash, scrubber:, normalizer: Ingest::PathNormalizer.new)
      file = normalizer.normalize(Ingest::TreeLimiter.truncate(hash["file"], Ingest::Limits::FRAME_FILE))
      new(file:, line: integer(hash["line"]), method_name: method_name(hash["method"]),
          in_app: in_app(hash["in_app"], file), gem_name: gem_name(file),
          context: Ingest::FrameContext.new(hash["context"], scrubber:).to_h,
          locals: Ingest::FrameContext.locals(hash["locals"], scrubber:))
    end

    def in_app_path?(file) = file.match?(APP_PATH) && !file.match?(VENDORED)

    def gem_name(file) = file[GEM_DIR, 1] || file[GEM_LIB, 1]

    private
      def integer(value)
        Integer(value, exception: false) if value.is_a?(Integer) || value.is_a?(String)
      end

      def method_name(value)
        Ingest::TreeLimiter.truncate(value, Ingest::Limits::FRAME_METHOD).presence if value.is_a?(String)
      end

      def in_app(flag, file)
        [ true, false ].include?(flag) ? flag : in_app_path?(file)
      end
  end

  def in_app? = in_app

  # "app/services/cart_total.rb:42 in line_total"
  def location
    [ [ file, line ].compact.join(":"), method_name&.then { "in #{it}" } ].compact.join(" ")
  end

  def to_h
    { file:, line:, method: method_name, in_app:, gem: gem_name, context:, locals: }
  end
end
