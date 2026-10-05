# The status chip on a projects overview card, derived from numbers only:
#
#   listening  no event has arrived yet
#   all_clear  nothing unresolved
#   spiking    the current hour has at least 10 events and at least 3x the
#              average of the previous 23 hours
#   steady     everything else
class ProjectHealth
  SPIKE_MINIMUM = 10
  SPIKE_FACTOR = 3
  STATUSES = %i[listening all_clear spiking steady].freeze

  attr_reader :project, :unresolved_count, :hourly_totals, :last_seen_at

  def initialize(project, unresolved_count:, hourly_totals:, last_seen_at:, now: Time.current)
    @project = project
    @unresolved_count = unresolved_count.to_i
    @hourly_totals = Array(hourly_totals)
    @last_seen_at = last_seen_at
    @now = now
  end

  def status
    @status ||= detect_status
  end

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  # Whole days since the last error (or since the first event when no issue exists).
  def days_clean
    since = last_seen_at || project.first_event_at || @now
    [ ((@now - since) / 1.day).floor, 0 ].max
  end

  private
    def detect_status
      return :listening if project.listening?
      return :all_clear if unresolved_count.zero?

      spike? ? :spiking : :steady
    end

    def spike?
      current = hourly_totals.last.to_i
      current >= SPIKE_MINIMUM && current >= SPIKE_FACTOR * previous_average
    end

    def previous_average
      previous = hourly_totals[0...-1]
      previous.empty? ? 0 : previous.sum.fdiv(previous.size)
    end
end
