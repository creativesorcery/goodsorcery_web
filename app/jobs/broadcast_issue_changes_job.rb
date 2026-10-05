# Sends live-update pointers for one issue. The only argument is the issue's
# GlobalID (plus a flag), so no captured data reaches the queue.
class BroadcastIssueChangesJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError # the issue was deleted meanwhile

  def perform(issue, created: false)
    frames = LiveFrames.new(issue.project, issue)

    if created
      frames.prepend_new_row
    else
      frames.issue_frames.each(&:reload)
    end
  end
end
