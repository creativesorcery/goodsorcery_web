# How an environment name reads at a glance, everywhere it is shown:
# production-like names are coral, staging-like lilac, local and test muted,
# anything else iris. Names match case-insensitively.
#
#   EnvironmentTone.of("Production")      # => :coral
#   EnvironmentTone.production?("live")  # => true
#   EnvironmentTone.of("eu-west")         # => :iris
module EnvironmentTone
  GROUPS = {
    coral: %w[production prod live],
    lilac: %w[staging stage preview qa uat],
    muted: %w[development dev test local]
  }.freeze
  OTHER = :iris
  TONES = [ *GROUPS.keys, OTHER ].freeze
  LOOKUP = GROUPS.flat_map { |tone, names| names.map { |name| [ name, tone ] } }.to_h.freeze

  module_function

  def of(name)
    LOOKUP.fetch(name.to_s.strip.downcase, OTHER)
  end

  def production?(name)
    of(name) == :coral
  end
end
