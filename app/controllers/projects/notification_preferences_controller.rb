# Saves the signed-in person's alert and digest switches for one app, from
# the Notifications page. Doesn't change the sidebar's remembered project.
class Projects::NotificationPreferencesController < ApplicationController
  before_action :set_project

  def update
    membership.update_notification_preference(@project, **preference_params)
    redirect_to notifications_path, notice: "Notification settings saved."
  end

  private
    def set_project
      @project = Current.account.projects.find_by!(slug: params[:project_id])
    end

    def membership
      Current.account.memberships.find_by!(user: Current.user)
    end

    def preference_params
      params.expect(notification_preference: %i[alerts_muted digest_enabled]).to_h.symbolize_keys
    end
end
