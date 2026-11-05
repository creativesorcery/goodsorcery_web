# Checks the required and typed fields of one trace.
class Apm::TracesEnvelope::TraceCheck
  include Apm::JsonShape

  LAYERS = %w[db_ms http_ms view_ms ruby_ms].freeze
  LABELS = %w[method route adapter queue host process].freeze

  def initialize(trace, path)
    @trace = trace
    @path = path
  end

  def check(errors)
    return errors.add("#{@path} must be an object") unless @trace.is_a?(Hash)

    [ identity_error, *time_errors, numbers_error, labels_error, outcome_error, spans_error ].compact
      .each { errors.add("#{@path}.#{it}") }
  end

  private
    def value(key) = @trace[key]

    def identity_error
      return "kind must be \"web\" or \"job\"" unless ApmTransaction::KINDS.include?(value("kind"))

      "name must be a non-empty string" unless value("name").is_a?(String) && value("name").strip.present?
    end

    def time_errors
      [ ("minute must be the UTC start of a minute" unless minute(value("minute"))),
        ("started_at must be an ISO 8601 timestamp" unless time(value("started_at"))),
        ("duration_ms must be a number >= 0" unless number?(value("duration_ms"))) ]
    end

    def numbers_error
      bad = LAYERS.find { !optional_number?(value(it)) }
      "#{bad} must be a number >= 0" if bad
    end

    def labels_error
      bad = LABELS.find { !optional_string?(value(it)) }
      "#{bad} must be a string" if bad
    end

    def outcome_error
      return "status must be an integer" unless value("status").nil? || integer?(value("status"), min: 0, max: 999)

      "failed must be a boolean" unless [ nil, true, false ].include?(value("failed"))
    end

    def spans_error
      "spans must be an array" unless value("spans").nil? || value("spans").is_a?(Array)
    end
end
