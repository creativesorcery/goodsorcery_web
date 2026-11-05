# Checks one entry of a metrics minute: kind, name, counts, duration, the
# sparse buckets (indexes 0..30 at most once, counts adding up to count,
# layer sums >= 0) and, for jobs, the queue-wait histogram.
class Apm::MetricsEnvelope::TransactionCheck
  include Apm::JsonShape

  LABELS = %w[method route adapter queue source].freeze

  def initialize(transaction, path)
    @transaction = transaction
    @path = path
  end

  def check(errors)
    return errors.add("#{@path} must be an object") unless @transaction.is_a?(Hash)

    [ identity_error, *count_errors, labels_error, buckets_error, queue_wait_error ].compact.each { errors.add("#{@path}.#{it}") }
  end

  private
    def value(key) = @transaction[key]

    def count = value("count")

    def identity_error
      return "kind must be \"web\" or \"job\"" unless ApmTransaction::KINDS.include?(value("kind"))

      "name must be a non-empty string" unless value("name").is_a?(String) && value("name").strip.present?
    end

    def count_errors
      [ ("count must be an integer of at least 1" unless integer?(count, min: 1)),
        ("failed must be an integer from 0 to count" unless integer?(value("failed"), min: 0, max: count.is_a?(Integer) ? count : nil)),
        ("duration_ms must be a number >= 0" unless number?(value("duration_ms"))),
        ("queue_wait_ms must be a number >= 0" unless optional_number?(value("queue_wait_ms"))) ]
    end

    def labels_error
      bad = LABELS.find { !optional_string?(value(it)) }
      "#{bad} must be a string" if bad
    end

    def buckets_error
      buckets = value("buckets")
      return "buckets must be an array of 1 to #{Apm::Histogram::BUCKETS} entries" unless list?(buckets, 1..Apm::Histogram::BUCKETS)
      return "buckets entries must be [index, count, db_ms, http_ms, view_ms, ruby_ms]" unless buckets.all? { bucket?(it) }
      return "buckets must not repeat an index" unless buckets.map(&:first).uniq.size == buckets.size

      "buckets must add up to count" unless buckets.sum { it[1] } == count
    end

    def bucket?(entry)
      entry.is_a?(Array) && entry.size == 6 && integer?(entry[0], min: 0, max: Apm::Histogram::LAST) &&
        integer?(entry[1], min: 1) && entry.drop(2).all? { number?(it) }
    end

    def queue_wait_error
      waits = value("queue_wait")
      return if waits.nil?
      return "queue_wait must be an array of at most #{Apm::Histogram::BUCKETS} entries" unless list?(waits, 0..Apm::Histogram::BUCKETS)
      return "queue_wait entries must be [index, count]" unless waits.all? { wait?(it) }
      return "queue_wait must not repeat an index" unless waits.map(&:first).uniq.size == waits.size

      "queue_wait must add up to at most count" if count.is_a?(Integer) && waits.sum(&:last) > count
    end

    def wait?(entry)
      entry.is_a?(Array) && entry.size == 2 && integer?(entry[0], min: 0, max: Apm::Histogram::LAST) && integer?(entry[1], min: 1)
    end
end
