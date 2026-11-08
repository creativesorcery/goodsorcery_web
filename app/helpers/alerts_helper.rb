# Settings › Alerts, the Notifications page and the mute link pages.
module AlertsHelper
  NOTIFICATION_ROW_GRID = "grid grid-cols-[minmax(0,1fr)_96px_96px_96px] gap-4".freeze

  RULE_COPY = {
    "new_issue" => [ "New issue", "The first time a brand-new issue happens." ],
    "regression" => [ "Regression", "A resolved issue happens again." ],
    "reached_production" => [ "Reached production", "An issue first seen in other environments happens in production." ],
    "still_happening" => [ "Still happening", "An issue's events in the last hour reach the threshold. At most once every 6 hours per issue." ],
    "daily_digest" => [ "Daily digest", "At 09:00 in each person's own time zone: open issues with events in the last 24 hours." ],
    "monitor_down" => [ "Monitor down", "A monitor fails its check, after one immediate retry." ],
    "monitor_recovered" => [ "Monitor recovered", "A monitor that was down passes its check again." ]
  }.freeze
  MUTE_SUBJECTS = { "alerts" => "email alerts", "uptime" => "uptime alerts", "digest" => "the daily digest" }.freeze

  def alert_rule_title(rule) = RULE_COPY.fetch(rule.kind).first

  def alert_rule_description(rule) = RULE_COPY.fetch(rule.kind).last

  # An aria-pressed switch that saves at once: a one-button form (PATCH).
  def switch_button_to(path, pressed:, params:, label:)
    button_to path, method: :patch, params:, class: "toggle inline-flex items-center p-1 -m-1",
      form_class: "contents", aria: { pressed:, label: }, title: label do
      tag.span(tag.span(class: "knob"), class: "track")
    end
  end

  # "production", "production, staging" in their tones, or "all environments",
  # from the saved settings (not a rejected form's values).
  def alert_environments_label(project)
    environments = project.saved_alert_environments
    return tag.span("all environments", class: "text-ink-300") if environments.nil?
    return tag.span("no environments", class: "text-ink-300") if environments.empty?

    safe_join(environments.map { |name| environment_text(name) }, ", ")
  end

  # The "follow the default" radio's label, naming what the default is now.
  def alert_default_scope_label(project)
    default = project.default_environment_in_database
    safe_join [ "Follow the default environment", " (", default ? environment_text(default) : "all environments", ")" ]
  end

  SLACK_STATUS_CHIPS = { "connected" => [ "Connected", :mint ], "off" => [ "Off", :muted ], "rejected" => [ "Turned off by Slack", :coral ] }.freeze

  # The Slack section's status: connected, off, or turned off because Slack rejected the webhook.
  def slack_status_chip(connection)
    label, tone = SLACK_STATUS_CHIPS.fetch(connection.status)
    chip label, tone:, small: true
  end

  def alert_mute_subject(alert_mute)
    MUTE_SUBJECTS.fetch(alert_mute.stream)
  end
end
