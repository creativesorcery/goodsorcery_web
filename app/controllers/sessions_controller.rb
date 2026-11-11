class SessionsController < ApplicationController
  include SignInThrottling

  layout "auth"

  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    return redirect_to(new_session_path, alert: "Try again later.") if sign_in_throttled?

    if user = User.authenticate_by(params.permit(:email_address, :password))
      remember_browser_for user.email_address
      start_new_session_for user
      redirect_to after_authentication_url
    else
      record_failed_sign_in
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
