# Wording for AlertsMailer (alerts, digests and summaries). Only an issue's
# redacted summary columns (title, exception class, transaction, culprit),
# environment names, numbers and times go into an email, never anything
# from an occurrence payload.
module AlertEmailsHelper
  INTROS = {
    "new_issue" => "A brand-new issue just happened for the first time.",
    "regression" => "An issue that was resolved is happening again.",
    "reached_production" => "An issue first seen in other environments now happens in production.",
    "still_happening" => "This issue keeps happening: its events in the last hour reached this app's threshold."
  }.freeze

  def alert_label(kind) = AlertsHelper::RULE_COPY.fetch(kind.to_s).first

  def alert_intro(kind) = INTROS.fetch(kind.to_s)

  # The issue's redacted message, or its exception class when it has none.
  def alert_issue_title(issue)
    issue.message.presence || issue.exception_class
  end

  # "CheckoutsController#create · app/services/cart_total.rb:42 in line_total"
  def alert_issue_origin(issue)
    [ issue.transaction_name, issue.culprit ].compact_blank.join(" · ")
  end

  # "Oct 11, 2026 09:14 BST" in the recipient's zone (the mailer sets it).
  def alert_time(time)
    time&.in_time_zone&.strftime("%b %-d, %Y %H:%M %Z")
  end

  def alert_events_line(issue)
    "#{pluralize(delimited(issue.events_count), 'event')} · #{pluralize(delimited(issue.users_count), 'user')} affected"
  end

  # "New issue: 3 · Regression: 1" for one app's folded alerts.
  def alert_summary_line(counts_by_kind)
    counts_by_kind.sort_by { |kind, _| AlertRule::KINDS.index(kind).to_i }
      .map { |kind, count| "#{alert_label(kind)}: #{delimited(count)}" }.join(" · ")
  end
end
