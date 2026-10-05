# Live updates for an issue (§4.4). Broadcasts are pointers only: frame ids
# and paths that each browser re-fetches with its own session, so nothing
# captured with an error ever reaches Action Cable or Redis pub/sub.
module Issue::Broadcasting
  extend ActiveSupport::Concern

  # At most this many brand-new issues per project are prepended live per
  # window; a storm of new fingerprints still shows in the summary counts.
  NEW_ROWS_PER_WINDOW = 10

  # New issues are prepended to open issue lists straight away. Every other
  # change is debounced to one broadcast per issue per LiveUpdateGate::WINDOW.
  def broadcast_changes_later(created: false)
    if created
      broadcast_creation_later
    else
      broadcast_update_later
    end
  end

  private
    def broadcast_creation_later
      return unless LiveUpdateGate.new(:new_issues, project_id).within_limit?(NEW_ROWS_PER_WINDOW)

      BroadcastIssueChangesJob.perform_later(self, created: true)
    end

    def broadcast_update_later
      return unless LiveUpdateGate.new(:issue, id).first_in_window?

      BroadcastIssueChangesJob.set(wait: LiveUpdateGate::WINDOW).perform_later(self)
    end
end
