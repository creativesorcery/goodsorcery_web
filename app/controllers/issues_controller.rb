class IssuesController < ApplicationController
  include ProjectScoped

  before_action :set_issue, only: :show

  def index
    @query = IssueQuery.from_params(params, user: Current.user)
    @list = IssueList.new(@project, @query, page: params[:page], sort: params[:sort])
    return render(partial: "issues/page", locals: { list: @list }) if load_more_request?

    @summary = IssueSummary.new(@project, environment: @query.environment)
    @members = Current.account.users.order(:name)
  end

  def show
    @occurrence = @issue.occurrences.latest
  end

  private
    def set_issue
      @issue = @project.issues.find_by_short_id!(params[:id])
    end

    # "load more" swaps the issues_page_<n> frame for just the next rows.
    def load_more_request?
      turbo_frame_request_id.to_s.start_with?("issues_page_")
    end
end
