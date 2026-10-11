# Which environment a project's issue list shows. In order of precedence:
#
# 1. an explicit choice in the request: an env: chip in the query, else the
#    env param (blank means all environments, so "All" can be chosen too);
# 2. the viewer's remembered choice for this project (a signed cookie);
# 3. the project's default_environment;
# 4. all environments.
#
# Remembered and default values count only while they are one of the
# project's environments (or blank, for all); anything else is ignored.
#
#   choice = EnvironmentChoice.new(project, query:, param: params[:env], remembered: cookie)
#   choice.environment # => "staging", or nil for all environments
class EnvironmentChoice
  ALL = "".freeze

  attr_reader :project, :requested

  def initialize(project, query: nil, param: nil, remembered: nil)
    @project = project
    @requested = query&.environment || requested_param(param)
    @remembered = remembered
  end

  # The environment shown, or nil for all of them.
  def environment
    return requested.presence if explicit?
    return @remembered.presence if known?(@remembered)

    project.default_environment if known?(project.default_environment)
  end

  def explicit? = !requested.nil?

  # Explicit choices of one of the project's environments, or of all, are
  # remembered for the next visit; an unknown env: chip is not.
  def remember? = explicit? && known?(requested)

  def environments
    @environments ||= project.environments
  end

  # Scoped to a single environment that is not production-like.
  def outside_production?
    environment.present? && !EnvironmentTone.production?(environment)
  end

  # The project's first production-like environment, if it has one.
  def production_environment
    environments.find { |name| EnvironmentTone.production?(name) }
  end

  private
    # Blank means all environments; otherwise it must look like an environment name.
    def requested_param(param)
      return unless param.is_a?(String)
      return ALL if param.strip.empty?

      param.downcase if ApiKey::ENVIRONMENT_FORMAT.match?(param.downcase)
    end

    def known?(value)
      value == ALL || (value.is_a?(String) && environments.include?(value))
    end
end
