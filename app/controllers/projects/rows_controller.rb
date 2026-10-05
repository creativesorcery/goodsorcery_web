# Issue-list rows re-fetched together by live updates (the `reload_rows`
# stream action): one request per viewer per window, whatever the number of
# changed rows, answered with a fixed number of queries.
class Projects::RowsController < ApplicationController
  include ProjectScoped

  MAX_IDS = 200

  def show
    @issues = @project.issues.where(id: requested_ids).includes(:assignee).to_a
    @histograms = @issues.empty? ? {} : IssueHourlyCount.histograms(@issues.map(&:id), hours: IssueList::HISTOGRAM_HOURS)
    render formats: :turbo_stream
  end

  private
    def requested_ids
      params[:ids].to_s.split(",").first(MAX_IDS).filter_map { |id| Integer(id, 10, exception: false) }
    end
end
