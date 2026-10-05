# Sends live-update pointers for one project's issue list summary and rows,
# overview card and setup listening panel. Its only argument is a GlobalID.
class BroadcastProjectChangesJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError # the project was deleted meanwhile

  def perform(project)
    LiveFrames.new(project).project_frames.each(&:reload)
  end
end
