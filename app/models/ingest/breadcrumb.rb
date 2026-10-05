# One normalised breadcrumb. `offset_ms` is relative to the event's occurred_at.
class Ingest::Breadcrumb < Data.define(:offset_ms, :category, :level, :message, :data)
  CATEGORIES = %w[request controller sql http cache log job custom].freeze
  LEVELS = %w[debug info warning error].freeze

  class << self
    # The most recent Ingest::Limits::BREADCRUMBS crumbs, oldest first.
    def list(value, occurred_at:, scrubber:)
      Array(value).grep(Hash).last(Ingest::Limits::BREADCRUMBS).map { |hash| from_hash(hash, occurred_at:, scrubber:) }
    end

    def from_hash(hash, occurred_at:, scrubber:)
      new(offset_ms: offset_ms(hash["timestamp"], occurred_at),
          category: pick(hash["category"], CATEGORIES, "custom"),
          level: pick(hash["level"], LEVELS, "info"),
          message: scrubber.scrub_text(Ingest::TreeLimiter.truncate(hash["message"], Ingest::Limits::BREADCRUMB_MESSAGE)),
          data: data(hash["data"], scrubber))
    end

    private
      def offset_ms(timestamp, occurred_at)
        time = Ingest::Timestamp.parse(timestamp)
        ((time - occurred_at) * 1000).round if time
      end

      def pick(value, allowed, default) = allowed.include?(value) ? value : default

      def data(value, scrubber)
        return {} unless value.is_a?(Hash)

        scrubber.scrub(Ingest::TreeLimiter.new.limit(value.first(Ingest::Limits::BREADCRUMB_DATA_KEYS).to_h))
      end
  end
end
