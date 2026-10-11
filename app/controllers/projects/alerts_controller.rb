# Settings › Alerts: the app's alert rules (switched by AlertRulesController)
# and the environments they watch. Like Settings › General, any member of
# the account can change them.
class Projects::AlertsController < ApplicationController
  include ProjectScoped

  def show
  end

  def update
    if @project.update(alert_scope_params)
      redirect_to project_alerts_path(@project), notice: "Alert environments saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def alert_scope_params
      params.expect(project: [ :alert_scope, alert_selected_environments: [] ])
    end
end
