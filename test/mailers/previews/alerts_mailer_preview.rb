require "active_support/testing/time_helpers"

# Preview all emails at http://localhost:3000/rails/mailers/alerts_mailer
# (needs the demo data: bin/rails db:seed). Each preview uses an unresolved
# issue inside its app's alert environments (or an uptime incident) and a
# verified member, or the mailer sends nothing.
#
# Demo data ages, so each email is rendered as if it were a minute after the
# issue was last seen: the digest then has its issue in the last 24 hours and
# "Last hour" isn't always 0. (travel_to stubs the clock process-wide while it
# renders; previews only run in development.)
class AlertsMailerPreview < ActionMailer::Preview
  include ActiveSupport::Testing::TimeHelpers

  def new_issue = issue_alert("new_issue")

  def regression = issue_alert("regression")

  def reached_production = issue_alert("reached_production")

  def still_happening = issue_alert("still_happening")

  def digest
    issue = alertable_issue
    just_after(issue) { AlertsMailer.digest(recipient(issue.project), issue.project) }
  end

  def summary
    projects = Project.order(:id).first(2)
    counts = projects.to_h { |project| [ project.id.to_s, { "new_issue" => 7, "regression" => 2 } ] }
    AlertsMailer.summary(recipient(projects.first), counts)
  end

  # The newest open incident, or an unsaved one on the first monitor.
  def monitor_down
    incident = UptimeIncident.open.order(:id).last || sample_incident(resolved_at: nil)
    AlertsMailer.monitor_down(recipient(incident.uptime_monitor.project), incident)
  end

  def monitor_recovered
    incident = UptimeIncident.where.not(resolved_at: nil).order(:id).last || sample_incident(resolved_at: Time.current)
    AlertsMailer.monitor_recovered(recipient(incident.uptime_monitor.project), incident)
  end

  # An unsaved, rejected connection when no app has one, so previews never write.
  def slack_disabled
    project = SlackConnection.where.not(disabled_at: nil).first&.project || Project.order(:id).first
    project.association(:slack_connection).target ||= SlackConnection.new(project_id: project.id, enabled: false,
      disabled_at: 1.hour.ago, disabled_reason: "channel_not_found")
    owner = project.account.memberships.owner.with_verified_email.first&.user || recipient(project)
    AlertsMailer.slack_disabled(owner, project)
  end

  private
    def sample_incident(resolved_at:)
      UptimeIncident.new(uptime_monitor: UptimeMonitor.order(:id).first, started_at: 14.minutes.ago, resolved_at:,
                         error_kind: "http_status", http_status: 503)
    end

    def issue_alert(kind)
      issue = alertable_issue
      just_after(issue) { AlertsMailer.issue_alert(recipient(issue.project), issue, kind) }
    end

    def alertable_issue
      Issue.unresolved.includes(:project).order(last_seen_at: :desc).limit(50)
        .find { |issue| issue.project.alerts_cover?(issue.environments) }
    end

    # Builds the message inside the block, while the clock is moved.
    def just_after(issue)
      travel_to(issue.last_seen_at + 1.minute) { yield.message }
    end

    def recipient(project)
      project.account.users.email_verified.first
    end
end
