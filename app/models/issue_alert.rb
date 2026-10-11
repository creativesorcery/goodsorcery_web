# One instant alert about one issue (new_issue, regression,
# reached_production or still_happening), decided and handed to the mailer
# for each recipient (ARCHITECTURE.md §11.4).
#
# Ingest only flags transitions (IssueAlert.transitions, read from what the
# counter UPDATE returned) and enqueues IssueAlertJob with ids and the kind.
# Everything else is decided here, at send time:
#
# - the app's rule for the kind is on;
# - the issue is still unresolved (ignored and resolved issues never alert);
# - the app's environment scope covers the triggering occurrence's
#   environment (or, without one, any of the issue's environments);
# - still_happening: nobody was alerted about the issue in the last 6 hours.
#
# Each recipient (verified members who haven't muted the app) then gets one
# AlertDelivery.claim: a duplicate key is skipped, an over-the-cap alert is
# folded into the hourly summary, and only "sent" ones are mailed.
#
#   IssueAlert.new(issue, "regression", occurrence_id: 42).deliver
class IssueAlert
  attr_reader :issue, :kind, :project

  # The rule kinds an ingested event triggered. `previous_status` and
  # `just_reached_production` come back from Ingest::IssueTally#count.
  def self.transitions(issue, created:)
    [ ("new_issue" if created),
      ("regression" if issue.previous_status == "resolved"),
      ("reached_production" if issue.just_reached_production) ].compact
  end

  def initialize(issue, kind, occurrence_id: nil)
    @issue, @kind, @occurrence_id = issue, kind.to_s, occurrence_id
    @project = issue.project
  end

  def due?
    issue.unresolved? && project.alert_rule_enabled?(kind) && project.alerts_cover?(environments) && !throttled?
  end

  # Returns the users it was mailed to (folded and duplicate claims aren't).
  def deliver
    return [] unless due?

    project.alert_recipients.select { |user| deliver_to(user) }
  end

  private
    def deliver_to(user)
      status = AlertDelivery.claim(user:, project:, issue:, kind:, dedupe_key: AlertDelivery.issue_key(kind, issue))
      AlertsMailer.issue_alert(user, issue, kind).deliver_later if status == "sent"
      status == "sent"
    end

    # The environment of the event that caused the transition, else the issue's.
    def environments
      environment = @occurrence_id && issue.occurrences.where(id: @occurrence_id).pick(:environment)
      environment ? [ environment ] : issue.environments
    end

    def throttled?
      kind == "still_happening" && AlertDelivery.alerted_recently?(issue, kind)
    end
end
