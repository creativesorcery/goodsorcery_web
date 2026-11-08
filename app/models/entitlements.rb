# What an account may use, as plain values (docs/ARCHITECTURE.md §12.2,
# §13.7). Self-hosted instances are unlimited and ignore stored values;
# their performance retention is the instance setting
# (config.x.apm_retention_days, GOODSORCERY_APM_RETENTION_DAYS), since
# unlimited retention is not sensible. Hosted ones use each stored value when
# it is present and valid, and the configured hosted default otherwise.
# Never queries; build one per use.
class Entitlements
  UPTIME_INTERVALS = [ 1, 5, 10, 60 ].freeze
  DEFAULT_UPTIME_INTERVAL = 10
  MAX_APM_RETENTION_DAYS = 30
  KEYS = %w[ uptime_intervals max_monitors apm_retention_days max_projects monthly_event_quota ].freeze
  # Keys whose value is a cap: nil (no cap) or a whole number of 0 or more.
  CAP_KEYS = %w[ max_monitors max_projects ].freeze

  # The self-hosted values of every key but apm_retention_days, which reads
  # the instance setting instead (#unlimited_value).
  UNLIMITED = { "uptime_intervals" => UPTIME_INTERVALS, "max_monitors" => nil, "max_projects" => nil,
                "monthly_event_quota" => nil }.freeze

  PROBLEMS = {
    "uptime_intervals" => "Uptime intervals must be a non-empty list of distinct values from #{UPTIME_INTERVALS.to_sentence}.",
    "max_monitors" => "Max monitors must be empty (no limit) or a whole number of 0 or more.",
    "apm_retention_days" => "APM retention days must be a whole number from 1 to #{MAX_APM_RETENTION_DAYS}.",
    "max_projects" => "Max projects must be empty (no limit) or a whole number of 0 or more.",
    "monthly_event_quota" => "Monthly event quota must be empty (no limit) or a whole number greater than 0."
  }.freeze

  # Whole-sentence messages for the known keys that hold invalid values.
  def self.problems(values)
    return [ "Entitlements must be an object of values." ] unless values.is_a?(Hash)

    values.stringify_keys.slice(*KEYS).filter_map { |key, value| PROBLEMS[key] unless valid_value?(key, value) }
  end

  def self.valid_value?(key, value)
    case key
    when "uptime_intervals" then valid_uptime_intervals?(value)
    when *CAP_KEYS then value.nil? || (value.is_a?(Integer) && value >= 0)
    when "apm_retention_days" then value.is_a?(Integer) && value.between?(1, MAX_APM_RETENTION_DAYS)
    when "monthly_event_quota" then value.nil? || (value.is_a?(Integer) && value.positive?)
    else false
    end
  end

  def self.valid_uptime_intervals?(value)
    value.is_a?(Array) && value.any? && value.uniq.size == value.size &&
      value.all? { |minutes| minutes.is_a?(Integer) && UPTIME_INTERVALS.include?(minutes) }
  end
  private_class_method :valid_uptime_intervals?

  def initialize(values, hosted: Rails.configuration.x.hosted,
                 hosted_defaults: Rails.configuration.x.entitlements.hosted_defaults, account_id: nil,
                 self_hosted_apm_retention_days: Rails.configuration.x.apm_retention_days)
    @values = values.is_a?(Hash) ? values.stringify_keys : {}
    @hosted = hosted
    @self_hosted_apm_retention_days = self_hosted_apm_retention_days.to_i.clamp(1, MAX_APM_RETENTION_DAYS)
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

  # Uptime monitors per app: an Integer, or nil for no cap.
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

  # Apps (projects) per account: an Integer, or nil for no cap.
  def max_projects
    resolved("max_projects")
  end

  def project_limit_reached?(count)
    !max_projects.nil? && count >= max_projects
  end

  # Error events accepted per UTC month: an Integer, or nil for no quota.
  # Ingest reads it through Account.over_quota?, cached.
  def monthly_event_quota
    resolved("monthly_event_quota")
  end

  # Days of performance data kept (1..30).
  def apm_retention_days
    resolved("apm_retention_days")
  end

  # Ranges of a day or less are always allowed.
  def allows_apm_range?(days) = days <= 1 || days <= apm_retention_days

  private
    def resolved(key)
      @resolved.fetch(key) { @resolved[key] = resolve(key) }
    end

    def resolve(key)
      return unlimited_value(key) if unlimited?
      return hosted_default(key) unless @values.key?(key)
      return normalize(key, @values[key]) if self.class.valid_value?(key, @values[key])

      Rails.logger.warn("Ignoring invalid entitlement #{key} for account #{@account_id}")
      hosted_default(key)
    end

    # A key missing from the configured defaults is unlimited.
    def hosted_default(key)
      normalize(key, @hosted_defaults.fetch(key) { unlimited_value(key) })
    end

    def unlimited_value(key)
      key == "apm_retention_days" ? @self_hosted_apm_retention_days : UNLIMITED.fetch(key)
    end

    def normalize(key, value)
      key == "uptime_intervals" ? value.sort.freeze : value
    end
end
