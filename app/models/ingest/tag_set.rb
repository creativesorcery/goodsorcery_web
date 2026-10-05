# Event tags: up to 25 valid client tags with scalar values (coerced to
# strings and scrubbed), plus server tags. Client tags win on key conflicts,
# except `environment`, which always comes from the API key.
class Ingest::TagSet
  SCALARS = [ String, Numeric, TrueClass, FalseClass ].freeze

  def initialize(client_tags, environment:, release:, host:, scrubber:)
    @client_tags = client_tags.is_a?(Hash) ? client_tags : {}
    @environment, @release, @host, @scrubber = environment, release, host, scrubber
  end

  def to_h
    @to_h ||= server_defaults.merge(client).merge("environment" => @environment)
  end

  private
    def server_defaults
      { "release" => @release, "host" => (tag_value(@host) if @host.is_a?(String)) }.compact_blank
    end

    def client
      valid = @client_tags.select { |key, value| key.match?(Ingest::Limits::TAG_KEY) && SCALARS.any? { value.is_a?(it) } }
      @scrubber.scrub(valid.first(Ingest::Limits::TAGS).to_h { |key, value| [ key, tag_value(value) ] }).compact_blank
    end

    def tag_value(value)
      Ingest::TreeLimiter.truncate(value, Ingest::Limits::TAG_VALUE).strip.presence unless value.nil?
    end
end
