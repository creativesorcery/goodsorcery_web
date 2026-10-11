class ApplicationController < ActionController::Base
  include Authentication, RemembersEnvironment

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :use_user_time_zone
  after_action :forbid_caching

  private
    def use_user_time_zone(&)
      Time.use_zone(Current.user&.time_zone || "UTC", &)
    end

    # Dashboard pages may show captured (personal) data: never store them in
    # browser or proxy caches.
    def forbid_caching
      no_store
    end
end
