# Live updates for a project (§4.4): the issue list summary and rows, the
# overview card and the setup page's listening panel, debounced to one
# pointer broadcast per project per LiveUpdateGate::WINDOW. The account-wide
# recent feed is debounced per account, so N busy projects still send one.
module Project::Broadcasting
  extend ActiveSupport::Concern

  def broadcast_changes_later
    broadcast_recent_issues_later
    return unless LiveUpdateGate.new(:project, id).first_in_window?

    BroadcastProjectChangesJob.set(wait: LiveUpdateGate::WINDOW).perform_later(self)
  end

  private
    def broadcast_recent_issues_later
      return unless LiveUpdateGate.new(:recent_issues, account_id).first_in_window?

      BroadcastRecentIssuesJob.set(wait: LiveUpdateGate::WINDOW).perform_later(account)
    end
end
