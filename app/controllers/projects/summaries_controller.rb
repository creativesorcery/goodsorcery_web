# The issue list heading and summary strip (frame dom_id(project, :summary)):
# re-fetched by the period switcher and by live updates.
class Projects::SummariesController < ApplicationController
  include ProjectScoped

  def show
    @summary = IssueSummary.new(@project, period: params[:period], environment: params[:env])
  end
end
