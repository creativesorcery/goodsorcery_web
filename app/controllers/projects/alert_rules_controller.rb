# Switches one alert rule on or off, or sets the still_happening threshold,
# from Settings › Alerts.
class Projects::AlertRulesController < ApplicationController
  include ProjectScoped

  before_action :set_alert_rule

  def update
    if @alert_rule.update(alert_rule_params)
      redirect_to project_alerts_path(@project), notice: "Alert rules saved."
    else
      render "projects/alerts/show", status: :unprocessable_entity
    end
  end

  private
    # From the loaded association, so a rejected change shows on the page.
    def set_alert_rule
      @alert_rule = @project.alert_rules.find { |rule| rule.kind == params[:kind] } || raise(ActiveRecord::RecordNotFound)
    end

    def alert_rule_params
      params.expect(alert_rule: %i[enabled threshold])
    end
end
