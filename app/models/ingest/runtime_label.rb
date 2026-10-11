# "Rails 8.0 · Ruby 3.4" from an event's context.runtime (major.minor only).
class Ingest::RuntimeLabel
  def initialize(runtime)
    @runtime = runtime.is_a?(Hash) ? runtime : {}
  end

  def to_s
    [ version_label("Rails", @runtime["rails"]), version_label("Ruby", @runtime["ruby"]) ].compact.join(" · ").presence
  end

  private
    def version_label(name, version)
      major_minor = version.to_s[/\A\s*(\d+\.\d+)/, 1]
      "#{name} #{major_minor}" if major_minor
    end
end
