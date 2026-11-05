# The figures the overview shows for one transaction over a range, taken
# from its merged histogram (Apm::Distribution): numbers only, so a hash of
# them is safe to cache (docs/ARCHITECTURE.md §13.11).
#
#   figures = Apm::Figures.from(distribution)
#   figures.percentile(95)  # => 412.7
#   Apm::Figures.from_a(figures.to_a) == figures
Apm::Figures = Data.define(:count, :failed, :duration_ms, :average_ms, :p50, :p75, :p90, :p95, :p99, :queue_wait_p95) do
  def self.from(distribution)
    percentiles = [ 50, 75, 90, 95, 99 ].map { distribution.percentile(it) }
    new(distribution.count, distribution.failed, distribution.duration_ms, distribution.average_ms, *percentiles,
        distribution.queue_wait_percentile(95))
  end

  def self.empty = from(Apm::Distribution.empty)

  # The inverse of #to_a (cached values).
  def self.from_a(values) = new(*values)

  def to_a = deconstruct

  def percentile(p) = public_send(:"p#{p}")

  def empty? = count.zero?

  def failed_rate = empty? ? nil : failed.fdiv(count)

  def rate_per_minute(minutes) = count / minutes.to_f
end
