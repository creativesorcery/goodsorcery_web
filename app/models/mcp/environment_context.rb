# An occurrence's environment context (the issue page's Environment tab)
# for get_occurrence. With the request_data scope it is all there, bounded.
# Without it only the runtime keys clients send (runtime, host, os,
# process, env) are kept, and the cause chain keeps each cause's class with
# its message redacted like issue titles (a wrapped PG::UniqueViolation says
# "Key (email)=(…)"). Custom keys the app added (scope.context, often user
# ids or emails) are left out and named in #omitted_keys.
#
#   context = Mcp::EnvironmentContext.new(occurrence.context, request_data: false)
#   context.to_h          # => { "runtime" => {…}, "host" => "web-2", "cause" => [{ "class" => …, "message" => … }] }
#   context.omitted_keys  # => ["tenant", "current_user_email"]
class Mcp::EnvironmentContext
  RUNTIME_KEYS = %w[runtime host os process env].freeze
  MAX_CAUSES = 3
  MAX_OMITTED_KEYS = 20

  def initialize(context, request_data:)
    @context = context.to_h
    @request_data = request_data
  end

  def to_h
    return @context if @request_data

    kept = @context.slice(*RUNTIME_KEYS)
    causes.any? ? kept.merge("cause" => causes) : kept
  end

  def omitted_keys
    return [] if @request_data

    (@context.keys - RUNTIME_KEYS - %w[cause]).first(MAX_OMITTED_KEYS).map { |key| Mcp::Captured.string(key, Mcp::Captured::MAX_KEY) }
  end

  private
    def causes
      @causes ||= Array(@context["cause"]).grep(Hash).first(MAX_CAUSES).map do |cause|
        { "class" => cause["class"].to_s, "message" => Ingest::MessageRedactor.new.redact(cause["message"].to_s) }
      end
    end
end
