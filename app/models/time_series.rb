# Aligns sparse { time => count } data onto a fixed run of equal UTC buckets,
# zero-filling the gaps and summing counts that fall into the same bucket.
#
#   TimeSeries.new({ 2.hours.ago => 3 }, from: TimeSeries.window_start(1.hour, 24), step: 1.hour, buckets: 24).values
class TimeSeries
  # Bucket boundaries are aligned to the Unix epoch, i.e. UTC hours and days.
  def self.align(time, step)
    seconds = step.to_i
    Time.zone.at((time.to_i / seconds) * seconds)
  end

  # Start of the first bucket so that the last bucket contains `now`.
  def self.window_start(step, buckets, now: Time.current)
    align(now, step) - ((buckets - 1) * step.to_i)
  end

  # How much of the current bucket has elapsed, 0.0...1.0.
  def self.elapsed_fraction(step, now: Time.current)
    (now - align(now, step)) / step.to_f
  end

  # SQL expression that bins the `hour` column into epoch-aligned buckets.
  def self.bucket_sql(step)
    Arel.sql(format("date_bin('%d seconds', hour, TIMESTAMP '1970-01-01')", step.to_i))
  end

  attr_reader :from, :step, :buckets

  def initialize(counts_by_time, from:, step:, buckets:)
    @counts_by_time = counts_by_time
    @from = self.class.align(from, step)
    @step = step.to_i
    @buckets = buckets
  end

  def values
    @values ||= fill(Array.new(buckets, 0))
  end

  def points
    values.each_with_index.map { |count, index| [ from + (index * step), count ] }
  end

  private
    def fill(slots)
      @counts_by_time.each do |time, count|
        index = (time.to_i - from.to_i).div(step)
        slots[index] += count.to_i if index.between?(0, buckets - 1)
      end
      slots
    end
end
