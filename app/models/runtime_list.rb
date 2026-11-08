# The runtimes an error event (context.runtime) or a trace (runtime) reports,
# in display order (docs/INGEST_API.md › Runtimes). Clients send display-ready
# names, so nothing here knows a language:
#
#   [{ "name" => "Rust", "version" => "1.82.0" }, { "name" => "axum", "version" => "0.8.1" }]
#
# The older object form, name → version, is still read (the Ruby gem 0.3.x
# sends { "ruby" => "3.4.1", "rails" => "8.0.1" }): its lowercase "ruby" and
# "rails" keys get their display names and Rails comes first, as before.
#
#   list = RuntimeList.new(context["runtime"])
#   list.label       # => "Rust 1.82 · axum 0.8" (major.minor, for the app's subtitle)
#   list.full_label  # => "Rust 1.82.0 · axum 0.8.1"
class RuntimeList
  # Display names are plaintext on the project row: a short, fixed alphabet
  # keeps anything personal out of them. Other names are dropped.
  NAME = %r{\A[A-Za-z0-9][\w .+#/-]{0,31}\z}
  VERSION = 64
  MAX_ENTRIES = 10
  LABEL_ENTRIES = 3
  LEGACY_NAMES = { "rails" => "Rails", "ruby" => "Ruby" }.freeze
  MAJOR_MINOR = /\A\s*v?(\d+(?:\.\d+)?)/

  Entry = Data.define(:name, :version) do
    def short_version = version.to_s[MAJOR_MINOR, 1]

    def to_h = { "name" => name, "version" => version }
  end

  def initialize(value)
    @value = value
  end

  def entries
    @entries ||= pairs.filter_map { |name, version| entry(name, version) }.uniq(&:name).first(MAX_ENTRIES)
  end

  def empty? = entries.empty?

  # The stored list form.
  def to_a = entries.map(&:to_h)

  # "Rails 8.0 · Ruby 3.4": up to three entries with a numeric version, or nil.
  def label
    entries.filter_map { |entry| entry.short_version&.then { "#{entry.name} #{it}" } }.first(LABEL_ENTRIES).join(" · ").presence
  end

  # "Ruby 3.4.1 · Rails 8.0.2" with full versions, or nil.
  def full_label = entries.map { [ it.name, it.version ].compact_blank.join(" ") }.join(" · ").presence

  private
    def pairs
      case @value
      when Array then @value.grep(Hash).map { |item| item.values_at("name", "version") }
      when Hash then legacy_pairs
      else []
      end
    end

    # Rails before Ruby, then any other keys in the order sent. A key without a
    # version is skipped: the Ruby gem 0.3.x sent "rails" => nil from plain-Ruby
    # apps, and that must not read as a Rails runtime.
    def legacy_pairs
      known, other = @value.select { |_, version| version_text(version) }.partition { |key, _| LEGACY_NAMES.key?(key) }
      known.sort_by { |key, _| LEGACY_NAMES.keys.index(key) }.map { |key, version| [ LEGACY_NAMES[key], version ] } + other
    end

    def entry(name, version)
      return unless name.is_a?(String) && name.strip.match?(NAME)

      Entry.new(name: name.strip, version: version_text(version))
    end

    def version_text(version)
      return unless version.is_a?(String) || version.is_a?(Numeric)

      version.to_s.strip.first(VERSION).presence
    end
end
