# Global search (top bar). A short id such as "GS-1042" jumps straight to that
# issue; anything else lists matching projects plus issues across the account,
# understanding the same chips as the issue list (is:, env:, level:, user: …).
class SearchesController < ApplicationController
  RESULT_LIMIT = 20
  PROJECT_LIMIT = 10

  def show
    @query = IssueQuery.new(params[:q].is_a?(String) ? params[:q] : "", user: Current.user)
    issue = short_id_match
    return redirect_to(project_issue_path(issue.project, issue)) if issue

    @projects = matching_projects
    @issues = matching_issues
  end

  private
    def account_projects
      Current.account.projects
    end

    def short_id_match
      prefix, number = @query.text.upcase.split("-", 2)
      return unless @query.chips.empty? && @query.text.match?(Issue::SHORT_ID)

      Issue.where(project: account_projects.where(issue_prefix: prefix).select(:id))
        .includes(:project).order(:id).find_by(number:)
    end

    def matching_projects
      return Project.none if @query.text.blank?

      pattern = "%#{Project.sanitize_sql_like(@query.text)}%"
      account_projects.where("projects.name ILIKE ?", pattern).order(:name).limit(PROJECT_LIMIT)
    end

    def matching_issues
      return Issue.none if @query.blank?

      @query.issues(Issue.where(project: account_projects.select(:id)))
        .sorted_by(IssueList::DEFAULT_SORT).includes(:project).limit(RESULT_LIMIT)
    end
end
