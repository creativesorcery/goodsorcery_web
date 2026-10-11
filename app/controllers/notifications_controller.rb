# The signed-in person's own alert emails, per app of the current account:
# instant alerts on or muted, and the daily digest on or off.
class NotificationsController < ApplicationController
  def show
    @membership = Current.account.memberships.includes(:notification_preferences).find_by!(user: Current.user)
    @projects = Current.account.projects.order(:name).includes(:alert_rules).to_a
  end
end
