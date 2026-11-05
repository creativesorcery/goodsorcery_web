# One merged duration histogram (docs/ARCHITECTURE.md §13.6): request and
# failure counts, the summed duration, the gs-v1 bucket counts, the summed
# time per layer of the requests in each bucket, and the queue-wait
# histogram of jobs. Immutable; #+ adds element-wise, so any set of minute or
# hour rows sums to one Distribution.
#
#   dist.average_ms           # => 164.2 (sum / count), nil when empty
#   dist.percentile(95)       # => 412.7, interpolated inside its bucket
#   dist.layer_split(95)      # => { db: 201.3, http: 0.0, view: 88.1, ruby: 123.3 }
#   dist.layer_split(:average)
class Apm::Distribution
  LAYERS = %i[db http view ruby].freeze
  ARRAYS = %i[counts db_ms http_ms view_ms ruby_ms queue_wait_counts].freeze
  SCALARS = %i[count failed duration_ms queue_wait_ms].freeze
  PERCENTILES = [ 50, 75, 90, 95, 99 ].freeze

  attr_reader(*SCALARS, *ARRAYS)

  def self.empty = new

  # From a payload's sparse buckets: [[index, count, db_ms, http_ms, view_ms,
  # ruby_ms], …] and queue wait [[index, count], …] (already validated).
  def self.from_buckets(count:, failed:, duration_ms:, buckets:, queue_wait: [], queue_wait_ms: 0.0)
    arrays = { counts: Apm::Histogram.zeros, queue_wait_counts: Apm::Histogram.zeros }
    %i[db_ms http_ms view_ms ruby_ms].each { arrays[it] = Apm::Histogram.float_zeros }
    buckets.each { |index, n, *layers| fill_bucket(arrays, index, n, layers) }
    queue_wait.each { |index, n| arrays[:queue_wait_counts][index] += n }
    new(count:, failed:, duration_ms: duration_ms.to_f, queue_wait_ms: queue_wait_ms.to_f, **arrays)
  end

  def self.fill_bucket(arrays, index, count, layers)
    arrays[:counts][index] += count
    %i[db_ms http_ms view_ms ruby_ms].zip(layers) { |key, ms| arrays[key][index] += ms.to_f }
  end
  private_class_method :fill_bucket

  # The inverse of #to_h (numbers only; safe to cache).
  def self.from_h(hash) = new(**hash.symbolize_keys.slice(*SCALARS, *ARRAYS))

  def initialize(count: 0, failed: 0, duration_ms: 0.0, queue_wait_ms: 0.0, counts: Apm::Histogram.zeros,
                 db_ms: Apm::Histogram.float_zeros, http_ms: Apm::Histogram.float_zeros, view_ms: Apm::Histogram.float_zeros,
                 ruby_ms: Apm::Histogram.float_zeros, queue_wait_counts: Apm::Histogram.zeros)
    @count, @failed, @duration_ms, @queue_wait_ms = count.to_i, failed.to_i, duration_ms.to_f, queue_wait_ms.to_f
    @counts, @queue_wait_counts = counts.map(&:to_i).freeze, queue_wait_counts.map(&:to_i).freeze
    @db_ms, @http_ms, @view_ms, @ruby_ms = [ db_ms, http_ms, view_ms, ruby_ms ].map { |list| list.map(&:to_f).freeze }
    freeze
  end

  def +(other)
    scalars = SCALARS.to_h { [ it, public_send(it) + other.public_send(it) ] }
    arrays = ARRAYS.to_h { |key| [ key, public_send(key).zip(other.public_send(key)).map(&:sum) ] }
    self.class.new(**scalars, **arrays)
  end

  def to_h = (SCALARS + ARRAYS).index_with { public_send(it) }

  def empty? = count.zero?

  def average_ms = empty? ? nil : duration_ms / count

  def failed_rate = empty? ? nil : failed.fdiv(count)

  def rate_per_minute(minutes) = minutes.to_f.positive? ? count / minutes.to_f : nil

  # Interpolated inside the bucket the rank falls in (§13.6); nil when empty.
  def percentile(p)
    bucket = bucket_for(p, counts)
    bucket && bucket_value(bucket, p, counts) { overflow_mean }
  end

  # The bucket a percentile falls in, or nil when empty.
  def percentile_bucket(p) = bucket_for(p, counts)

  # { db:, http:, view:, ruby: } in ms, summing to the bar's value: the
  # average in the proportions of all layer time, or a percentile in the
  # proportions of the layer sums of the bucket it falls in.
  def layer_split(which)
    value = which == :average ? average_ms : percentile(which)
    return if value.nil?

    split(value, which == :average ? layer_totals : layer_sums_at(percentile_bucket(which)))
  end

  def layer_totals = { db: db_ms.sum, http: http_ms.sum, view: view_ms.sum, ruby: ruby_ms.sum }

  def layer_sums_at(bucket) = { db: db_ms[bucket], http: http_ms[bucket], view: view_ms[bucket], ruby: ruby_ms[bucket] }

  def queue_wait_count = queue_wait_counts.sum

  def queue_wait_average_ms = queue_wait_count.zero? ? nil : queue_wait_ms / queue_wait_count

  # Same interpolation; the open bucket reports its lower bound (48 s).
  def queue_wait_percentile(p)
    bucket = bucket_for(p, queue_wait_counts)
    bucket && bucket_value(bucket, p, queue_wait_counts) { Apm::Histogram::BOUNDS_MS.last.to_f }
  end

  private
    def rank(p, total) = (Rational(p) * total / 100).ceil.clamp(1, total)

    def bucket_for(p, list)
      total = list.sum
      return if total.zero?

      target = rank(p, total)
      running = 0
      list.index { |n| (running += n) >= target }
    end

    def bucket_value(bucket, p, list)
      return yield if bucket == Apm::Histogram::LAST

      fraction = (rank(p, list.sum) - list.first(bucket).sum - 0.5) / list[bucket]
      interpolate(bucket, fraction)
    end

    # Linear in bucket 0 (0..1 ms), geometric between the bucket's bounds otherwise.
    def interpolate(bucket, fraction)
      bounds = Apm::Histogram::BOUNDS_MS
      return fraction * bounds[0] if bucket.zero?

      lower, upper = bounds[bucket - 1].to_f, bounds[bucket].to_f
      lower * ((upper / lower)**fraction)
    end

    # Requests of 48 s or more: their own mean, at least the bucket's bound.
    def overflow_mean
      last = Apm::Histogram::LAST
      [ layer_sums_at(last).values.sum / counts[last], Apm::Histogram::BOUNDS_MS.last.to_f ].max
    end

    def split(value, sums)
      total = sums.values.sum
      return { db: 0.0, http: 0.0, view: 0.0, ruby: value.to_f } unless total.positive?

      db, http, view = %i[db http view].map { value * sums[it] / total }
      { db:, http:, view:, ruby: [ value - db - http - view, 0.0 ].max }
    end
end
