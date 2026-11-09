# Live frame: the setup page's "Listening for your first event…" panel. Once
# the first event has landed it also refreshes the hero, its stepper and the
# rail's MCP card.
class Projects::ListeningsController < ApplicationController
  include ProjectScoped

  def show
    @progress = SetupProgress.new(@project)
    render layout: false
  end
end
