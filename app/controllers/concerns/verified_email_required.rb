# Actions that need a confirmed email address: creating apps and API keys.
# Unverified users can still sign in and look around; the dashboard banner
# (layouts/_email_verification) tells them how to confirm.
module VerifiedEmailRequired
  extend ActiveSupport::Concern

  class_methods do
    def require_verified_email(**options)
      before_action :require_verified_email, **options
    end
  end

  private
    def require_verified_email
      return if Current.user.email_verified?

      redirect_back_or_to root_path, status: :see_other,
        alert: "Confirm your email address first: use the link we sent to #{Current.user.email_address}."
    end
end
