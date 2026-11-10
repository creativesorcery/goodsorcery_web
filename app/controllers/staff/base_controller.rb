# The staff area (/staff): accounts, users and entitlements across every
# account, so nothing here is scoped through Current.account. Signed-out
# visitors and signed-in non-staff get the same 404 as a path that doesn't
# exist, so the area's existence isn't revealed.
class Staff::BaseController < ApplicationController
  include Pagy::Method

  PER_PAGE = 25

  layout "staff"

  # First in the chain, ahead of the CSRF check (422) and allow_browser
  # (406): either would answer a real staff route differently from an
  # unknown path.
  prepend_before_action :require_staff

  private
    # Runs before require_authentication, so it resumes the session itself
    # (memoized in Current.session).
    def require_staff
      raise_not_found unless resume_session&.user&.staff?
    end

    # Signed out: a 404 instead of the sign-in redirect (Authentication). A
    # backstop, since require_staff has already turned them away.
    def request_authentication
      raise_not_found
    end

    def raise_not_found
      raise ActionController::RoutingError, "Not Found"
    end

    # [pagy, records] for one page of an index, newest first.
    def paginate(scope)
      pagy(:offset, scope.order(id: :desc), limit: PER_PAGE)
    end

    helper_method def search_query
      params[:q].to_s.strip.presence
    end
end
