# The issue list's environment choice (EnvironmentChoice), remembered per
# project in one signed cookie: a small hash of project id => environment
# name ("" for all environments), keeping only the most recently chosen
# projects so the cookie stays small however many apps a viewer opens.
#
# Turbo prefetches links on hover, so a prefetch request never remembers
# anything; the views also turn prefetch off for the links that change the
# list's scope, so a real click is always a fresh request.
module RemembersEnvironment
  extend ActiveSupport::Concern

  COOKIE = :issues_environments
  COOKIE_LIFETIME = 1.year
  REMEMBERED_PROJECTS = 20

  included do
    helper_method :issues_environment_for
  end

  private
    # Resolves the issue list's environment for this request and remembers an
    # explicit choice.
    def choose_environment(project, query)
      @environment_choice = EnvironmentChoice.new(project, query:, param: params[:env], remembered: remembered_environment(project))
      remember_environment(@environment_choice) if @environment_choice.remember? && !prefetch_request?
      @environment_choice
    end

    # The environment a project's issue list shows (and the sidebar badge
    # counts): this request's choice on the issue list, otherwise the
    # remembered one, the project's default or all (nil).
    def issues_environment_for(project)
      return @environment_choice.environment if @environment_choice&.project == project

      @issues_environments ||= {}
      return @issues_environments[project.id] if @issues_environments.key?(project.id)

      @issues_environments[project.id] = EnvironmentChoice.new(project, remembered: remembered_environment(project)).environment
    end

    def remembered_environment(project)
      remembered_environments[project.id.to_s]
    end

    # The newest choice goes last; the oldest ones drop off.
    def remember_environment(choice)
      key = choice.project.id.to_s
      choices = remembered_environments.except(key).merge(key => choice.requested).to_a.last(REMEMBERED_PROJECTS).to_h
      cookies.signed[COOKIE] = { value: choices, expires: COOKIE_LIFETIME.from_now, httponly: true, same_site: :lax }
    end

    def remembered_environments
      choices = cookies.signed[COOKIE]
      choices.is_a?(Hash) ? choices : {}
    end

    def prefetch_request?
      request.headers["X-Sec-Purpose"] == "prefetch" || request.headers["Sec-Purpose"].to_s.include?("prefetch")
    end
end
