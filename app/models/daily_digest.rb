# One app's daily digest: its open (unresolved) issues with events in the
# last 24 hours, within the app's alert environment scope, busiest first.
#
# SendDailyDigestsJob runs hourly. Each run mails the digest recipients
# whose local time (users.time_zone) is in the 09:00 hour, once per user,
# app and local date (AlertDelivery.digest_key): a repeated or late run
# within that hour sends nothing twice, and DST changes (which never move
# 09:00 to another date) can't double it. Nothing is sent when no issue
# qualifies. Digests don't count towards the hourly alert cap.
#
#   DailyDigest.deliver_due
#   digest = DailyDigest.new(project)
#   digest.issues          # up to LISTED, each with #recent_events
#   digest.issue_count
class DailyDigest
  LOCAL_HOUR = 9
  LISTED = 10
  WINDOW = 24.hours

  attr_reader :project

  def self.deliver_due(now: Time.current)
    AlertRule.enabled.daily_digest.includes(:project).find_each do |rule|
      new(rule.project, now:).deliver
    end
  end

  def initialize(project, now: Time.current)
    @project, @now = project, now
  end

  # Returns the users it was mailed to.
  def deliver
    recipients = due_recipients
    return [] if recipients.empty? || issue_count.zero?

    recipients.select { |user| deliver_to(user) }
  end

  def due_recipients
    project.digest_recipients.select { |user| local_time(user).hour == LOCAL_HOUR }
  end

  # The busiest open issues, each with `recent_events` (events in the window).
  def issues
    @issues ||= open_issues.joins(:hourly_counts).where(issue_hourly_counts: { hour: TimeSeries.align(since, 1.hour).. })
      .group(:id).select("issues.*", "SUM(issue_hourly_counts.count) AS recent_events")
      .order(Arel.sql("SUM(issue_hourly_counts.count) DESC"), id: :desc).limit(LISTED).to_a
  end

  def issue_count
    @issue_count ||= open_issues.count
  end

  def more_count = [ issue_count - issues.size, 0 ].max

  private
    def since = @now - WINDOW

    def open_issues
      relation = project.issues.unresolved.where(last_seen_at: since..)
      environments = project.alert_environments
      environments ? relation.where("issues.environments && ARRAY[?]::varchar[]", environments) : relation
    end

    def local_time(user) = @now.in_time_zone(user.time_zone)

    def deliver_to(user)
      key = AlertDelivery.digest_key(project, local_time(user).to_date)
      return false unless AlertDelivery.record(user:, project:, kind: :daily_digest, dedupe_key: key)

      AlertsMailer.digest(user, project).deliver_later
      true
    end
end
