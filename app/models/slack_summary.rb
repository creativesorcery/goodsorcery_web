# The hourly "and N more alerts" Slack post (docs/ARCHITECTURE.md §11.5),
# run by SendAlertSummariesJob after AlertSummary. Issue alerts an app posted
# over SlackDelivery::HOURLY_CAP were recorded `folded`; after each clock
# hour, every app with folded rows from before it gets one summary post with
# the counts per kind.
#
# In one transaction the summary row is recorded first (a nil insert means
# this hour's summary was already claimed), then the folded rows are marked
# `summarized_at`. Folded rows from the current hour wait for the next run.
#
#   SlackSummary.post_due
#   SlackSummary.new(project).post_later   # => the summary delivery, or nil
class SlackSummary
  attr_reader :project

  def self.post_due(now: Time.current)
    project_ids = SlackDelivery.awaiting_summary.where(created_at: ...now.beginning_of_hour).distinct.pluck(:project_id)
    Project.where(id: project_ids).find_each { |project| new(project, now:).post_later }
  end

  def initialize(project, now: Time.current)
    @project, @now = project, now
  end

  def post_later
    delivery = claim_folded
    SlackPostJob.perform_later(delivery.id) if delivery
    delivery
  end

  private
    def folded = SlackDelivery.where(project:).awaiting_summary.where(created_at: ...@now.beginning_of_hour)

    def claim_folded
      SlackDelivery.transaction do
        counts = folded.group(:kind).count
        next if counts.empty?

        SlackDelivery.record(project:, kind: :summary, summary_counts: counts, at: @now)
          &.tap { folded.update_all(summarized_at: @now) }
      end
    end
end
