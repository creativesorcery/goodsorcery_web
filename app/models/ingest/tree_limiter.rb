# Bounds arbitrary JSON trees (request, params, headers, session, context,
# breadcrumb data): nesting depth, array length, hash size and string length.
class Ingest::TreeLimiter
  TRUNCATED = "[truncated]".freeze

  def initialize(depth: Ingest::Limits::DEPTH, items: Ingest::Limits::ARRAY_ITEMS,
                 keys: Ingest::Limits::HASH_KEYS, string: Ingest::Limits::STRING)
    @max_depth, @items, @keys, @string = depth, items, keys, string
  end

  def limit(value, depth = 1)
    case value
    when Hash then nested(depth) { limit_hash(value, depth) }
    when Array then nested(depth) { value.first(@items).map { |item| limit(item, depth + 1) } }
    when String then self.class.truncate(value, @string)
    else value
    end
  end

  def self.truncate(text, max)
    text = text.to_s
    text.length > max ? "#{text[0, max - 1]}…" : text
  end

  private
    def nested(depth)
      depth > @max_depth ? TRUNCATED : yield
    end

    def limit_hash(hash, depth)
      hash.first(@keys).to_h do |key, value|
        [ self.class.truncate(key, Ingest::Limits::KEY), limit(value, depth + 1) ]
      end
    end
end
