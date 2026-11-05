# The "Slower" flag (docs/ARCHITECTURE.md §13.6): a transaction whose p95 in
# the last hour is at least Apm::SLOWER_RATIO times its p95 over the past 24
# hours (which include that hour), with at least SLOWER_MIN_LAST_HOUR
# requests in the hour and SLOWER_MIN_PAST_DAY in the day. No "vs previous
# day" comparisons exist anywhere.
#
#   Apm::Slower.new(stats).ratios(ids)   # => { id => 1.8 } for the slower ones only
class Apm::Slower
  def self.ratio(last_hour, past_day)
    return unless last_hour.count >= Apm::SLOWER_MIN_LAST_HOUR && past_day.count >= Apm::SLOWER_MIN_PAST_DAY

    recent, usual = last_hour.percentile(95), past_day.percentile(95)
    ratio = recent / usual if recent && usual&.positive?
    ratio if ratio && ratio >= Apm::SLOWER_RATIO
  end

  def initialize(stats)
    @stats = stats
  end

  def ratios(ids)
    last_hour, past_day = @stats.last_hour(ids), @stats.past_day(ids)
    ids.each_with_object({}) do |id, result|
      ratio = self.class.ratio(last_hour.fetch(id) { Apm::Distribution.empty }, past_day.fetch(id) { Apm::Distribution.empty })
      result[id] = ratio if ratio
    end
  end

  def ratio(id) = ratios([ id ])[id]
end
