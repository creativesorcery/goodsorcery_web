# One normalised backtrace frame. Paths are normalised, code context and
# locals are bounded and scrubbed. `to_h` is the stored payload shape (§3.3).
#
# The client's in_app flag and package name are trusted as sent. Only when a
# client leaves them out does the server guess from Ruby-style paths
# (app/, lib/ and config/ outside gems/ and vendor/bundle; gems/<name>-<version>/)
# and Cargo registry paths (crates/<name>-<version>/ once normalised).
class Ingest::Frame < Data.define(:file, :line, :column, :method_name, :module_name, :in_app, :package, :context, :locals)
  APP_PATH = %r{\A(?:app|lib|config)/}
  VENDORED = %r{/gems/|vendor/bundle}
  PACKAGE_DIR = %r{(?:\A|/)(?:gems|crates)/([^/]+?)-(?:\d|\h{7,})[^/]*/}
  GEM_LIB = %r{(?:\A|/)([A-Za-z][\w.-]*?)-\d[\w.]*/lib/}

  class << self
    def from_hash(hash, scrubber:, normalizer: Ingest::PathNormalizer.new)
      file = normalizer.normalize(Ingest::TreeLimiter.truncate(hash["file"], Ingest::Limits::FRAME_FILE))
      new(file:, line: integer(hash["line"]), column: integer(hash["column"]), method_name: name(hash["method"]),
          module_name: name(hash["module"]), in_app: in_app(hash["in_app"], file),
          package: name(hash["package"]) || package_from_path(file),
          context: Ingest::FrameContext.new(hash["context"], scrubber:).to_h,
          locals: Ingest::FrameContext.locals(hash["locals"], scrubber:))
    end

    def in_app_path?(file) = file.match?(APP_PATH) && !file.match?(VENDORED)

    def package_from_path(file) = file[PACKAGE_DIR, 1] || file[GEM_LIB, 1]

    private
      def integer(value)
        number = Integer(value, exception: false) if value.is_a?(Integer) || value.is_a?(String)
        number if number&.between?(0, 2**31 - 1)
      end

      def name(value)
        Ingest::TreeLimiter.truncate(value, Ingest::Limits::FRAME_METHOD).strip.presence if value.is_a?(String)
      end

      def in_app(flag, file)
        [ true, false ].include?(flag) ? flag : in_app_path?(file)
      end
  end

  def in_app? = in_app

  # "app/services/cart_total.rb:42 in line_total" (no column: the culprit
  # stays the same when a line is reformatted).
  def location
    [ [ file, line ].compact.join(":"), method_name&.then { "in #{it}" } ].compact.join(" ")
  end

  def to_h
    { file:, line:, method: method_name, in_app:, package:, context:, locals: }.merge({ column:, module: module_name }.compact)
  end
end
