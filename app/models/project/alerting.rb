# An app's alert settings: its rules (AlertRule, one per kind), the
# environments they watch, and who receives the emails.
#
#   project.alert_rule(:new_issue).enabled?
#   project.alert_environments            # => ["production"], or nil for all
#   project.alerts_cover?(issue.environments)
#   project.alert_recipients              # => users to email right now
#   project.uptime_alert_recipients       # => users to email about monitors
#   project.slack_alerts_enabled?         # => posts to its Slack channel (§11.5)
module Project::Alerting
  extend ActiveSupport::Concern

  included do
    has_many :alert_rules, inverse_of: :project # rows cascade in the database
    has_many :alert_deliveries, inverse_of: :project
    has_many :notification_preferences, inverse_of: :project
    has_one :slack_connection, inverse_of: :project # rows cascade in the database
    has_many :slack_deliveries

    # "default" follows default_environment (nil there means all).
    enum :alert_scope, { follow_default: "default", all: "all", selected: "selected" }, prefix: true, validate: true

    normalizes :alert_selected_environments,
      with: ->(names) { Array(names).map { |name| name.to_s.strip.downcase }.compact_blank.uniq }

    # The picked environments only mean something with the "selected" scope.
    before_validation -> { self.alert_selected_environments = [] }, unless: :alert_scope_selected?
    validate :alert_selected_environments_known, if: :alert_scope_selected?

    after_create :create_default_alert_rules
  end

  # The rule of that kind (one query loads all of them, then memoised by the
  # association); an unsaved default if the row is missing.
  def alert_rule(kind)
    alert_rules.find { |rule| rule.kind == kind.to_s } || AlertRule.build_default(self, kind)
  end

  def alert_rules_in_order(kinds = AlertRule::ERROR_KINDS)
    kinds.map { |kind| alert_rule(kind) }
  end

  def alert_rule_enabled?(kind) = alert_rule(kind).enabled?

  # Does the app send any uptime alert (down or recovered)?
  def uptime_alerts_enabled? = AlertRule::UPTIME_KINDS.any? { |kind| alert_rule_enabled?(kind) }

  def still_happening_threshold = alert_rule(:still_happening).threshold

  # Does the app post alerts to a Slack channel right now?
  def slack_alerts_enabled? = slack_connection&.enabled? || false

  # The environments alerts watch, or nil for all of them.
  def alert_environments
    watched_environments(alert_scope, alert_selected_environments, default_environment)
  end

  # The same from the saved settings, so a rejected form still shows what applies.
  def saved_alert_environments
    watched_environments(alert_scope_in_database, alert_selected_environments_in_database, default_environment_in_database)
  end

  # Does the alert scope include any of these environments (an event's, or an issue's)?
  def alerts_cover?(environments)
    scope = alert_environments
    scope.nil? || scope.intersect?(Array(environments))
  end

  # Members with a confirmed address who haven't muted this app's alerts.
  def alert_recipients
    User.where(id: account.memberships.receiving_alerts_for(self).select(:user_id))
  end

  # Members with a confirmed address who haven't muted this app's uptime alerts.
  def uptime_alert_recipients
    User.where(id: account.memberships.receiving_uptime_alerts_for(self).select(:user_id))
  end

  # Members with a confirmed address who haven't turned off this app's digest.
  def digest_recipients
    User.where(id: account.memberships.receiving_digest_for(self).select(:user_id))
  end

  private
    def create_default_alert_rules
      AlertRule.insert_all(AlertRule.default_rows_for(self), unique_by: %i[project_id kind])
    end

    def watched_environments(scope, selected, default)
      return selected if scope == "selected"
      return if scope == "all" || default.nil?

      [ default ]
    end

    # Messages are whole sentences, shown without the attribute name.
    def alert_selected_environments_known
      if alert_selected_environments.empty?
        errors.add(:alert_selected_environments, :blank, message: "Pick at least one environment.")
      elsif (alert_selected_environments - environments).any?
        errors.add(:alert_selected_environments, :inclusion, message: "Pick from this app's environments.")
      end
    end
end
