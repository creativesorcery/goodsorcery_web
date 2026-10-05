# Reloads the overview's account-wide recent issues feed. Debounced per
# account (Project::Broadcasting), so many busy projects send one pointer per
# window. Its only argument is the account's GlobalID.
class BroadcastRecentIssuesJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError # the account was deleted meanwhile

  def perform(account)
    LiveFrames.recent_issues(account).reload
  end
end
