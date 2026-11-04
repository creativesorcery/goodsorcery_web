# Alert emails (ARCHITECTURE.md §11.4, §12.9): an instant alert about one
# issue, an app's daily digest, the hourly "and N more alerts" summary, and
# an uptime monitor going down or recovering.
#
# Arguments are records (GlobalIDs in the mail job), kind strings and, for the
# summary, counts per app id and kind: never captured data. Each email checks
# again when it is sent: the issue must still be unresolved (resolved and
# ignored issues never alert), and the recipient must still be a verified
# member who hasn't switched that stream off. Times show in the recipient's
# zone. Alerts and digests carry a one-click List-Unsubscribe link (AlertMute)
# for that app and stream.
#
# Uptime emails name the monitor and its host only, never the URL's path or
# query, which may hold tokens.
class AlertsMailer < ApplicationMailer
  helper :alert_emails, :number, :uptime

  SUBJECT_TITLE_LENGTH = 100

  def issue_alert(user, issue, kind)
    @user, @issue, @kind, @project = user, issue, kind.to_s, issue.project
    return unless issue.unresolved? && membership_for(@project)&.receives_alerts?(@project)

    @issue_url = project_issue_url(@project, issue)
    @last_hour_events = IssueHourlyCount.trailing_hour(issue) if @kind == "still_happening"
    allow_unsubscribe(@project, "alerts")
    mail_in_zone "#{AlertsHelper::RULE_COPY.fetch(@kind).first} in #{@project.name}: #{subject_title(issue)}"
  end

  def digest(user, project)
    @user, @project, @digest = user, project, DailyDigest.new(project)
    return unless membership_for(project)&.receives_digest?(project) && @digest.issue_count.positive?

    @issues_url = project_issues_url(project)
    allow_unsubscribe(project, "digest")
    count = @digest.issue_count
    mail_in_zone "Daily digest for #{project.name}: #{count} open #{'issue'.pluralize(count)} in the last 24 hours"
  end

  # counts: { "project_id" => { "kind" => n } }, from AlertSummary.
  def summary(user, counts)
    @user = user
    @projects = Project.where(id: counts.keys, account_id: user.memberships.select(:account_id)).order(:name).to_a
    return if @projects.empty? || !user.email_verified?

    @counts = counts.slice(*@projects.map { |project| project.id.to_s })
    @total = @counts.values.sum { |by_kind| by_kind.values.sum }
    @open_url = @projects.one? ? project_issues_url(@projects.first) : projects_url
    allow_unsubscribe(@projects.first, "alerts") if @projects.one?
    mail_in_zone "And #{@total} more #{'alert'.pluralize(@total)} from Good Sorcery"
  end

  def monitor_down(user, incident)
    assign_uptime(user, incident)
    return unless incident.open? && uptime_recipient?

    mail_in_zone "Down: #{@monitor.name} in #{@project.name}"
  end

  def monitor_recovered(user, incident)
    assign_uptime(user, incident)
    return if incident.open? || !uptime_recipient?

    mail_in_zone "Recovered: #{@monitor.name} in #{@project.name} after #{view_context.uptime_duration(incident.duration)}"
  end

  private
    def assign_uptime(user, incident)
      @user, @incident, @monitor = user, incident, incident.uptime_monitor
      @project = @monitor.project
    end

    # Checked at send time; on success sets the links the email needs.
    def uptime_recipient?
      return false unless membership_for(@project)&.receives_uptime_alerts?(@project)

      @monitor_url = project_uptime_monitor_url(@project, @monitor)
      allow_unsubscribe(@project, "uptime")
      true
    end

    def membership_for(project)
      project.account.memberships.find_by(user: @user)
    end

    def subject_title(issue)
      (issue.message.presence || issue.exception_class).squish.truncate(SUBJECT_TITLE_LENGTH)
    end

    # RFC 2369 and RFC 8058 one-click: mail providers POST to the link.
    def allow_unsubscribe(project, stream)
      @mute_url = alert_mute_url(token: @user.alert_mute_token(project, stream:))
      headers["List-Unsubscribe"] = "<#{@mute_url}>"
      headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    end

    def mail_in_zone(subject)
      Time.use_zone(@user.time_zone) { mail(to: @user.email_address, subject:) }
    end
end
