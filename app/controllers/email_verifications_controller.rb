# Confirms a user's email address from the link in the verification email
# (show), and sends a fresh link from the dashboard banner (create).
class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :show
  rate_limit to: 3, within: 10.minutes, only: :create, name: "resend", by: -> { Current.user.id },
             store: Ingest::RateLimitStore, with: -> { redirect_back_or_to root_path, alert: "Try again in a few minutes." }

  def show
    if (user = User.find_by_email_verification_token(params[:token]))
      user.verify_email
      redirect_to after_verification_path, notice: "Thanks, your email address is confirmed."
    else
      redirect_to after_verification_path, alert: "That confirmation link is invalid or has expired. Sign in to get a new one."
    end
  end

  def create
    Current.user.send_email_verification unless Current.user.email_verified?
    redirect_back_or_to root_path, notice: "We sent a new confirmation link to #{Current.user.email_address}."
  end

  private
    def after_verification_path
      authenticated? ? root_path : new_session_path
    end
end
