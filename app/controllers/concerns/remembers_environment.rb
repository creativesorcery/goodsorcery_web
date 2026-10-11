# The issue list's environment choice (EnvironmentChoice), remembered per
# project in a signed cookie that holds only an environment name ("" for
# all environments). The cookie's name carries the project id, and a signed
# value only verifies under the name it was written for, so one project's
# choice never applies to another.
module RemembersEnvironment
  extend ActiveSupport::Concern

  COOKIE_LIFETIME = 1.year

  included do
    helper_method :issues_environment_for
  end

  private
    # Resolves the issue list's environment for this request and remembers an
    # explicit choice.
    def choose_environment(project, query)
      @environment_choice = EnvironmentChoice.new(project, query:, param: params[:env], remembered: remembered_environment(project))
      remember_environment(@environment_choice) if @environment_choice.remember?
      @environment_choice
    end

    # The environment a project's issue list shows (and the sidebar badge
    # counts): this request's choice on the issue list, otherwise the
    # remembered one, the project's default or all (nil).
    def issues_environment_for(project)
      return @environment_choice.environment if @environment_choice&.project == project

      EnvironmentChoice.new(project, remembered: remembered_environment(project)).environment
    end

    def remembered_environment(project)
      cookies.signed[environment_cookie(project)]
    end

    def remember_environment(choice)
      cookies.signed[environment_cookie(choice.project)] = {
        value: choice.requested, expires: COOKIE_LIFETIME.from_now, httponly: true, same_site: :lax
      }
    end

    def environment_cookie(project) = "issues_environment_#{project.id}"
end
