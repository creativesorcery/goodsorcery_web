# One attempt's total time budget, on the monotonic clock. UptimeProbe sets
# every network timeout to #remaining before each hop and checks #remaining!
# between hops and body chunks.
class UptimeProbe::Deadline
  class Exceeded < StandardError
    def initialize(message = "Uptime check budget exceeded") = super
  end

  def initialize(seconds)
    @ends_at = now + seconds
  end

  def remaining = [ @ends_at - now, 0 ].max

  def expired? = remaining.zero?

  # The remaining seconds, or raises Exceeded when none are left.
  def remaining!
    raise Exceeded if expired?

    remaining
  end

  private
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
