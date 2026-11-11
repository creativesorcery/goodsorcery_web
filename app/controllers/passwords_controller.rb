class PasswordsController < ApplicationController
  include SignInThrottling # rate_limit_by_email, and remember_browser_for after a reset

  RESET_NOTICE = "Password reset instructions sent (if user with that email address exists).".freeze

  layout "auth"

  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }
  # Over the per-address limit, answer exactly as if the mail had been sent:
  # an error here would let anyone show the real user "Try again later".
  rate_limit_by_email(to: 5, within: 1.hour, only: :create) { redirect_to new_session_path, notice: RESET_NOTICE }

  def new
  end

  def create
    if user = User.find_by(email_address: email_address_param)
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: RESET_NOTICE
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.terminate_all # and their open live-update connections
      @user.verify_email # the reset link reached their inbox
      remember_browser_for @user.email_address # so an address lockout can't keep them out
      redirect_to new_session_path, notice: "Password has been reset."
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
