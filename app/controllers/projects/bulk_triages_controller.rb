# Resolve / ignore / reopen / assign up to 100 selected issues of a project at
# once (the floating bulk bar and the per-row buttons), then back to the list.
class Projects::BulkTriagesController < ApplicationController
  include ProjectScoped

  TRIAGES = { "resolve" => :resolve_all, "ignore" => :ignore_all, "reopen" => :reopen_all }.freeze
  DONE = { "resolve" => "Resolved", "ignore" => "Ignored", "reopen" => "Reopened", "assign" => "Assigned" }.freeze

  def create
    return back_to_list(alert: "Select at least one issue.") if selected_ids.empty?
    return back_to_list(alert: "Choose Resolve, Ignore, Reopen or an assignee.") unless triage_kind

    changed = triage(@project.issues.where(id: selected_ids))
    back_to_list(notice: "#{DONE.fetch(triage_kind)} #{helpers.pluralize(changed.size, 'issue')}.")
  end

  private
    def selected_ids
      ids = params[:issue_ids]
      @selected_ids ||= ids.is_a?(Array) ? ids.grep(/\A\d+\z/).first(Issue::Triage::BULK_LIMIT) : []
    end

    def triage_kind
      return "assign" if assignee

      params[:triage].to_s if TRIAGES.key?(params[:triage].to_s)
    end

    # Only members of the signed-in account can be assigned.
    def assignee
      return if params[:assignee_id].blank?

      @assignee ||= Current.account.users.find_by(id: params[:assignee_id])
    end

    def triage(issues)
      return issues.assign_all(assignee, by: Current.user) if assignee

      issues.public_send(TRIAGES.fetch(params[:triage].to_s), by: Current.user)
    end

    def back_to_list(**flash)
      redirect_back_or_to project_issues_path(@project), status: :see_other, **flash
    end
end
