# What an account may use, as plain values (docs/ARCHITECTURE.md §12.2).
# Self-hosted instances are unlimited and ignore stored values. Hosted ones use
# each stored value when it is present and valid, and the configured hosted
# default otherwise. Never queries; build one per use.
class Entitlements
  UPTIME_INTERVALS = [ 1, 5, 10, 60 ].freeze
  DEFAULT_UPTIME_INTERVAL = 10
  KEYS = %w[ uptime_intervals max_monitors ].freeze

  UNLIMITED = { "uptime_intervals" => UPTIME_INTERVALS, "max_monitors" => nil }.freeze

  PROBLEMS = {
    "uptime_intervals" => "Uptime intervals must be a non-empty list of distinct values from #{UPTIME_INTERVALS.to_sentence}.",
    "max_monitors" => "Max monitors must be empty (no limit) or a whole number of 0 or more."
  }.freeze

  # Whole-sentence messages for the known keys that hold invalid values.
  def self.problems(values)
    return [ "Entitlements must be an object of values." ] unless values.is_a?(Hash)

    values.stringify_keys.slice(*KEYS).filter_map { |key, value| PROBLEMS[key] unless valid_value?(key, value) }
  end

  def self.valid_value?(key, value)
    case key
    when "uptime_intervals" then valid_uptime_intervals?(value)
    when "max_monitors" then value.nil? || (value.is_a?(Integer) && value >= 0)
    else false
    end
  end

  def self.valid_uptime_intervals?(value)
    value.is_a?(Array) && value.any? && value.uniq.size == value.size &&
      value.all? { |minutes| minutes.is_a?(Integer) && UPTIME_INTERVALS.include?(minutes) }
  end
  private_class_method :valid_uptime_intervals?

  def initialize(values, hosted: Rails.configuration.x.hosted,
                 hosted_defaults: Rails.configuration.x.entitlements.hosted_defaults, account_id: nil)
    @values = values.is_a?(Hash) ? values.stringify_keys : {}
    @hosted = hosted
    @hosted_defaults = hosted_defaults.to_h.stringify_keys
    @account_id = account_id
    @resolved = {}
  end

  def unlimited? = !@hosted

  def uptime_intervals
    resolved("uptime_intervals")
  end

  def allows_uptime_interval?(minutes) = uptime_intervals.include?(minutes)

  def locked_uptime_intervals = UPTIME_INTERVALS - uptime_intervals

  def default_uptime_interval
    return DEFAULT_UPTIME_INTERVAL if allows_uptime_interval?(DEFAULT_UPTIME_INTERVAL)

    nearest_uptime_interval(DEFAULT_UPTIME_INTERVAL)
  end

  # The smallest allowed interval at least this long, else the longest allowed.
  def nearest_uptime_interval(minutes)
    uptime_intervals.find { |allowed| allowed >= minutes } || uptime_intervals.last
  end

  # An Integer, or nil for no cap.
  def max_monitors
    resolved("max_monitors")
  end

  def monitor_limit_reached?(count)
    !max_monitors.nil? && count >= max_monitors
  end

  def monitors_left(count)
    return if max_monitors.nil?

    [ max_monitors - count, 0 ].max
  end

  private
    def resolved(key)
      @resolved.fetch(key) { @resolved[key] = resolve(key) }
    end

    def resolve(key)
      return UNLIMITED.fetch(key) if unlimited?
      return hosted_default(key) unless @values.key?(key)
      return normalize(key, @values[key]) if self.class.valid_value?(key, @values[key])

      Rails.logger.warn("Ignoring invalid entitlement #{key} for account #{@account_id}")
      hosted_default(key)
    end

    # A key missing from the configured defaults is unlimited.
    def hosted_default(key)
      normalize(key, @hosted_defaults.fetch(key) { UNLIMITED.fetch(key) })
    end

    def normalize(key, value)
      key == "uptime_intervals" ? value.sort.freeze : value
    end
end
