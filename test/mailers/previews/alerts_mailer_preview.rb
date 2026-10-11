# Preview all emails at http://localhost:3000/rails/mailers/alerts_mailer
# (needs the demo data: bin/rails db:seed). Each preview uses an unresolved
# issue and a verified member, or the mailer sends nothing.
class AlertsMailerPreview < ActionMailer::Preview
  def new_issue = issue_alert("new_issue")

  def regression = issue_alert("regression")

  def reached_production = issue_alert("reached_production")

  def still_happening = issue_alert("still_happening")

  def digest
    issue = Issue.unresolved.order(last_seen_at: :desc).first
    AlertsMailer.digest(recipient(issue.project), issue.project)
  end

  def summary
    projects = Project.order(:id).first(2)
    counts = projects.to_h { |project| [ project.id.to_s, { "new_issue" => 7, "regression" => 2 } ] }
    AlertsMailer.summary(recipient(projects.first), counts)
  end

  private
    def issue_alert(kind)
      issue = Issue.unresolved.order(last_seen_at: :desc).first
      AlertsMailer.issue_alert(recipient(issue.project), issue, kind)
    end

    def recipient(project)
      project.account.users.email_verified.first
    end
end
