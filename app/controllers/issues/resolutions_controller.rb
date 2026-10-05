# Resolve (create) or reopen (destroy) an issue.
class Issues::ResolutionsController < ApplicationController
  include IssueScoped

  def create
    @issue.resolve(by: Current.user)
    redirect_to project_issue_path(@project, @issue), notice: "#{@issue.short_id} resolved.", status: :see_other
  end

  def destroy
    @issue.reopen(by: Current.user)
    redirect_to project_issue_path(@project, @issue), notice: "#{@issue.short_id} reopened.", status: :see_other
  end
end
