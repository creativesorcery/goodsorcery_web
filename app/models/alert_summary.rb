# The "and N more alerts" email: once a user has had AlertDelivery::HOURLY_CAP
# instant alerts in an hour, further ones are recorded as `folded` instead of
# mailed. SendAlertSummariesJob runs just after each hour and sends every
# user with folded deliveries from before that hour one summary of them
# (counts per app and rule), then marks them summarized.
#
# The summary row (kind "summary", AlertDelivery.summary_key) is recorded in
# the same transaction, so a repeated run in the same hour sends nothing
# twice. The mailer gets the counts (ids, kinds and numbers), not the rows.
#
#   AlertSummary.deliver_due
#   AlertSummary.new(user).deliver   # => { "12" => { "new_issue" => 3 } } or nil
class AlertSummary
  attr_reader :user

  def self.deliver_due(now: Time.current)
    before = now.beginning_of_hour
    user_ids = AlertDelivery.awaiting_summary.where(created_at: ...before).distinct.pluck(:user_id)
    User.where(id: user_ids).find_each { |user| new(user, now:).deliver }
  end

  def initialize(user, now: Time.current)
    @user, @now = user, now
  end

  # Returns the counts it mailed, or nil when there was nothing to send.
  def deliver
    counts = claim_folded
    AlertsMailer.summary(user, counts).deliver_later if counts.present?
    counts.presence
  end

  private
    def folded = AlertDelivery.where(user:).awaiting_summary.where(created_at: ...@now.beginning_of_hour)

    def claim_folded
      AlertDelivery.transaction do
        first = folded.order(:id).first
        next unless first && record_summary(first.project)

        counts_by_project.tap { folded.update_all(summarized_at: @now) }
      end
    end

    # The summary row names the first app it covers (project_id is required).
    def record_summary(project)
      AlertDelivery.record(user:, project:, kind: :summary, dedupe_key: AlertDelivery.summary_key(@now))
    end

    # { "project_id" => { "kind" => count } }, string keys so it serialises as a job argument.
    def counts_by_project
      folded.group(:project_id, :kind).count.each_with_object({}) do |((project_id, kind), count), counts|
        (counts[project_id.to_s] ||= {})[kind] = count
      end
    end
end
