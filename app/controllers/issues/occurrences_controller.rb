# One stored occurrence of an issue (a uuid, or latest / oldest / random),
# shown on the full issue page. The navigator's links target the "occurrence"
# frame, which advances the URL.
class Issues::OccurrencesController < ApplicationController
  include IssueScoped

  def show
    @occurrence_navigator = OccurrenceNavigator.new(@issue)
    @occurrence = @occurrence_navigator.find(params[:id])
    render "issues/show"
  end
end
