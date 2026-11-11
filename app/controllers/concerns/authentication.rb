module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return unless (id = cookies.signed[:session_id])

      Session.active.includes(:user, :account).find_by(id:)&.tap(&:record_activity)
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    # A fresh Rails session (new CSRF token, nothing left from before) for the
    # signed-in user; only the page they were heading to carries over.
    def start_new_session_for(user)
      reset_session_keeping_return_to
      session_attributes = { account: user.default_account, user_agent: request.user_agent, ip_address: request.remote_ip }
      user.sessions.create!(session_attributes).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax, expires: session.expires_at }
      end
    end

    def terminate_session
      Current.session.terminate
      cookies.delete(:session_id)
      reset_session
    end

    def reset_session_keeping_return_to
      return_to = session[:return_to_after_authenticating]
      reset_session
      session[:return_to_after_authenticating] = return_to if return_to
    end
end
