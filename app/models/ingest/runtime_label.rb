# "Rails 8.0 · Ruby 3.4" from an event's context.runtime (major.minor only).
class Ingest::RuntimeLabel
  def initialize(runtime, api: false)
    @runtime = runtime.is_a?(Hash) ? runtime : {}
    @api = api
  end

  def to_s
    [ rails_part, version_label("Ruby", @runtime["ruby"]) ].compact.join(" · ").presence
  end

  private
    def rails_part
      label = version_label("Rails", @runtime["rails"])
      label && @api ? "#{label} API" : label
    end

    def version_label(name, version)
      major_minor = version.to_s[/\A\s*(\d+\.\d+)/, 1]
      "#{name} #{major_minor}" if major_minor
    end
end
