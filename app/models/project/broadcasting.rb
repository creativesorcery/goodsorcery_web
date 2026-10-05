# Live updates for a project (§4.4): the issue list summary, the overview
# card and recent feed, and the setup page's listening panel. Debounced to
# one pointer broadcast per project per LiveUpdateGate::WINDOW.
module Project::Broadcasting
  extend ActiveSupport::Concern

  def broadcast_changes_later
    return unless LiveUpdateGate.new(:project, id).first_in_window?

    BroadcastProjectChangesJob.set(wait: LiveUpdateGate::WINDOW).perform_later(self)
  end
end
