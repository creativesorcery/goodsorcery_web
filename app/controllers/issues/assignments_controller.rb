# Assign an issue to a member of the current account, or unassign it.
class Issues::AssignmentsController < ApplicationController
  include IssueScoped

  def update
    assignee = Current.account.users.find(params.require(:assignee_id))
    @issue.assign(assignee, by: Current.user)
    redirect_to project_issue_path(@project, @issue), notice: "Assigned to #{assignee.name}.", status: :see_other
  end

  def destroy
    @issue.unassign(by: Current.user)
    redirect_to project_issue_path(@project, @issue), notice: "#{@issue.short_id} unassigned.", status: :see_other
  end
end
