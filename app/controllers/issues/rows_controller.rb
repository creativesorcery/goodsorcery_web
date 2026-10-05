# One issue-list row, re-fetched by live updates (frame dom_id(issue, :row)).
class Issues::RowsController < ApplicationController
  include IssueScoped

  def show
    @histogram = IssueHourlyCount.histograms([ @issue.id ], hours: IssueList::HISTOGRAM_HOURS).fetch(@issue.id)
  end
end
