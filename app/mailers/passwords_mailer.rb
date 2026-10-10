class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @url = edit_password_url(token: user.password_reset_token)
    mail subject: "Reset your password", to: user.email_address
  end
end
