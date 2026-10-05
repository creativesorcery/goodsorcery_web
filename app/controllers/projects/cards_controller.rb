# Live frame: one projects overview card.
class Projects::CardsController < ApplicationController
  include ProjectScoped

  def show
    @card = ProjectOverview.new([ @project ]).card_for(@project)
    render layout: false
  end
end
