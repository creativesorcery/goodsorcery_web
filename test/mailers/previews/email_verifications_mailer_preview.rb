# Preview all emails at http://localhost:3000/rails/mailers/email_verifications_mailer
class EmailVerificationsMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/email_verifications_mailer/verify
  def verify
    EmailVerificationsMailer.verify(User.take)
  end
end
