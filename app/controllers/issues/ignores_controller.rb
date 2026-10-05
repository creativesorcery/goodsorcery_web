# Ignore (create) an issue, or stop ignoring it, which reopens it (destroy).
class Issues::IgnoresController < ApplicationController
  include IssueScoped

  def create
    @issue.ignore(by: Current.user)
    redirect_to project_issue_path(@project, @issue), notice: "#{@issue.short_id} ignored.", status: :see_other
  end

  def destroy
    @issue.reopen(by: Current.user)
    redirect_to project_issue_path(@project, @issue), notice: "#{@issue.short_id} reopened.", status: :see_other
  end
end
