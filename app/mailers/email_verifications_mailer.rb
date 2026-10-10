class EmailVerificationsMailer < ApplicationMailer
  def verify(user)
    @user = user
    @url = email_verification_url(token: user.email_verification_token)
    mail subject: "Confirm your email address", to: user.email_address
  end
end
