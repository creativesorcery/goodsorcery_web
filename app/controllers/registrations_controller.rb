class RegistrationsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access
  before_action :require_signups_enabled
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @signup = Signup.new
  end

  def create
    @signup = Signup.new(signup_params)

    if (user = @signup.save)
      start_new_session_for user
      redirect_to root_path, notice: "Welcome to Good Sorcery. Add a new app to start catching errors."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def signup_params
      params.expect(signup: %i[account_name name email_address password time_zone])
    end

    def require_signups_enabled
      redirect_to new_session_path, alert: "Sign-ups are disabled." unless helpers.signups_enabled?
    end
end
