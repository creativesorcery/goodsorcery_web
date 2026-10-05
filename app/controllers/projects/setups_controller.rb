# Settings › Setup & API keys: the onboarding stepper, install snippets,
# the listening panel and the project's ingest keys.
class Projects::SetupsController < ApplicationController
  include ProjectScoped

  def show
    @progress = SetupProgress.new(@project)
    @api_keys = @project.api_keys.includes(:created_by).to_a
  end
end
