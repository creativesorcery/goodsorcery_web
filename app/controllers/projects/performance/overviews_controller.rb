# Performance overview of an app (docs/ARCHITECTURE.md §13.9 screen 1): KPI
# tiles, where request time goes, and the endpoints or jobs by time consumed.
class Projects::Performance::OverviewsController < ApplicationController
  include PerformanceScoped

  def show
    @overview = Apm::Overview.new(@project, performance_selection)
  end
end
