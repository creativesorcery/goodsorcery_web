# The one-click mute behind every alert email's List-Unsubscribe header.
# GET shows a confirmation page (link scanners never mute anything); POST
# mutes. No sign-in: the signed, expiring token (?token=) names the person,
# the app and the stream (alerts or digest). Mail clients POST here without
# a CSRF token (RFC 8058) and no cookie is involved, so forgery protection is
# skipped for create only. Any browser may open it (mail apps use old
# in-app browsers), so the modern-browser gate is off.
class AlertMutesController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection only: :create
  rate_limit to: 30, within: 1.minute, name: "alert_mute", store: Ingest::RateLimitStore

  layout "auth"

  before_action :set_alert_mute

  def show
  end

  def create
    @alert_mute.apply
  end

  private
    def any_browser_allowed? = true

    def set_alert_mute
      @alert_mute = AlertMute.find_by_token(params[:token])
      render :invalid, status: :not_found unless @alert_mute
    end
end
