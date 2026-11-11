require "test_helper"

class AlertsMailerTest < ActionMailer::TestCase
  # Captured data in the nomethod occurrence fixtures (locals, params,
  # headers, session, user, breadcrumbs, context, tags): none of it may
  # appear in an alert email. Only the issue's redacted summary columns may.
  CAPTURED = [ "mara@example.com", "Mara Lindqvist", "5521", "81.2.69.160", "FALL25", "CartItem", "variant_id",
               "Mobile Safari", "iPhone", "shop.acme.dev", "web-7f9c-2", "taxjar", "discontinued variant", "puma",
               "a1b2c3d", "88123" ].freeze

  setup do
    @user = users(:alex) # Europe/London
    @project = projects(:storefront)
    @issue = issues(:nomethod)
  end

  test "an issue alert names the rule, app, issue and environments, and links to the issue" do
    mail = AlertsMailer.issue_alert(@user, @issue, "new_issue")
    html = mail.html_part.body.to_s

    assert_equal [ @user.email_address ], mail.to
    assert_equal "New issue in storefront: undefined method `price_cents' for nil", mail.subject
    assert_includes html, "New issue in storefront"
    assert_includes html, "GS-1042"
    assert_includes html, "NoMethodError"
    assert_includes html, "undefined method `price_cents&#39; for nil"
    assert_includes html, "CheckoutsController#create · app/services/cart_total.rb:42 in line_total"
    assert_includes html, "1,284 events · 212 users affected"
    assert_match %r{<span style="[^"]*color: #cf4657;">production</span>}, html, "production in its coral tone"
    assert_includes html, "http://example.com/projects/storefront/issues/GS-1042"
  end

  test "times show in the recipient's zone" do
    local = @issue.first_seen_at.in_time_zone("Europe/London").strftime("%b %-d, %Y %H:%M %Z")

    assert_includes AlertsMailer.issue_alert(@user, @issue, "new_issue").html_part.body.to_s, local
    assert_includes AlertsMailer.issue_alert(@user, @issue, "new_issue").text_part.body.to_s, local
  end

  test "has a plain-text part that isn't HTML-escaped" do
    text = AlertsMailer.issue_alert(@user, @issue, "regression").text_part.body.to_s

    assert_includes text, "Regression in storefront"
    assert_includes text, "undefined method `price_cents' for nil"
    assert_includes text, "Environments: production"
    assert_includes text, "http://example.com/projects/storefront/issues/GS-1042"
    assert_includes text, "Notification settings: http://example.com/notifications"
    assert_not_includes text, "&#39;"
  end

  test "carries one-click List-Unsubscribe headers that mute this app's alerts for this person" do
    mail = AlertsMailer.issue_alert(@user, @issue, "new_issue")
    url = mail["List-Unsubscribe"].value[/\A<(.+)>\z/, 1]

    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].value
    assert_includes mail.html_part.body.to_s, url, "the footer's mute link"
    mute = AlertMute.find_by_token(Rack::Utils.parse_query(URI(url).query)["token"])
    assert_equal [ @user, @project, "alerts" ], [ mute.user, mute.project, mute.stream ]
  end

  test "the footer links to the Notifications page" do
    assert_includes AlertsMailer.issue_alert(@user, @issue, "new_issue").html_part.body.to_s, "http://example.com/notifications"
  end

  test "still happening shows the trailing hour against the threshold" do
    IssueHourlyCount.where(issue: @issue).delete_all
    IssueHourlyCount.create!(issue: @issue, hour: Time.current.beginning_of_hour, count: 140)
    text = AlertsMailer.issue_alert(@user, @issue, "still_happening").text_part.body.to_s

    assert_includes text, "Last hour: 140 events (threshold 100)"
  end

  test "an issue alert contains no captured data beyond the redacted title" do
    assert_no_captured_data AlertsMailer.issue_alert(@user, @issue, "new_issue")
    assert_no_captured_data AlertsMailer.issue_alert(@user, @issue, "still_happening")
  end

  test "escapes the issue title in HTML and keeps line breaks out of the subject" do
    @issue.update_columns(message: "<script>alert(1)</script>\nsecond line")
    mail = AlertsMailer.issue_alert(@user, @issue, "new_issue")

    assert_includes mail.html_part.body.to_s, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_not_includes mail.html_part.body.to_s, "<script>alert(1)"
    assert_equal "New issue in storefront: <script>alert(1)</script> second line", mail.subject
  end

  test "checked at send time: nothing for resolved or ignored issues" do
    assert_emails(0) { AlertsMailer.issue_alert(@user, issues(:resolved_issue), "regression").deliver_now }
    assert_emails(0) { AlertsMailer.issue_alert(@user, issues(:ignored_issue), "still_happening").deliver_now }
  end

  test "checked at send time: nothing for muted, unverified or non-members" do
    assert_emails(0) { AlertsMailer.issue_alert(users(:jo), issues(:billing_timeout), "new_issue").deliver_now }
    assert_emails(0) { AlertsMailer.issue_alert(users(:outsider), @issue, "new_issue").deliver_now }

    users(:jo).update_columns(email_verified_at: nil)
    assert_emails(0) { AlertsMailer.issue_alert(users(:jo), @issue, "new_issue").deliver_now }
  end

  test "the digest lists the app's open issues with their 24h events and links" do
    mail = AlertsMailer.digest(@user, @project)
    html = mail.html_part.body.to_s
    count = DailyDigest.new(@project).issue_count

    assert_equal "Daily digest for storefront: #{count} open issues in the last 24 hours", mail.subject
    assert_includes html, "GS-1042 · NoMethodError"
    assert_includes html, "http://example.com/projects/storefront/issues/GS-1042"
    assert_includes html, "Europe/London"
    assert_not_includes html, "GS-1010", "the ignored issue"
    assert_includes mail.text_part.body.to_s, "undefined method `price_cents' for nil"
    assert_no_captured_data mail
  end

  test "the digest's unsubscribe link stops this app's digest only" do
    url = AlertsMailer.digest(@user, @project)["List-Unsubscribe"].value[/\A<(.+)>\z/, 1]
    mute = AlertMute.find_by_token(Rack::Utils.parse_query(URI(url).query)["token"])

    assert_equal [ @project, "digest" ], [ mute.project, mute.stream ]
  end

  test "no digest for members who turned it off, or when nothing is open" do
    memberships(:alex_acme).update_notification_preference(@project, digest_enabled: false)
    assert_emails(0) { AlertsMailer.digest(@user, @project).deliver_now }

    assert_emails(0) { AlertsMailer.digest(users(:jo), projects(:marketing)).deliver_now }
  end

  test "the summary counts the folded alerts per app" do
    counts = { @project.id.to_s => { "new_issue" => 3, "regression" => 1 }, projects(:billing).id.to_s => { "still_happening" => 2 } }
    mail = AlertsMailer.summary(@user, counts)
    text = mail.text_part.body.to_s

    assert_equal "And 6 more alerts from Good Sorcery", mail.subject
    assert_includes text, "storefront: New issue: 3 · Regression: 1"
    assert_includes text, "billing-api: Still happening: 2"
    assert_nil mail["List-Unsubscribe"], "covers more than one app"
    assert_includes mail.html_part.body.to_s, "And 6 more alerts"
    assert_includes mail.html_part.body.to_s, "paste this link into your browser"
    assert_match %r{^http\S+/projects$}, text
  end

  test "the summary of one app can mute it, and never shows another account's apps" do
    counts = { @project.id.to_s => { "new_issue" => 2 }, projects(:umbrella_app).id.to_s => { "new_issue" => 5 } }
    mail = AlertsMailer.summary(@user, counts)

    assert_equal "And 2 more alerts from Good Sorcery", mail.subject
    assert_not_includes mail.text_part.body.to_s, "umbrella"
    assert mail["List-Unsubscribe"]
    assert_emails(0) { AlertsMailer.summary(users(:outsider), counts.except(projects(:umbrella_app).id.to_s)).deliver_now }
  end

  test "a down email names the monitor, app, host, cause and since, and links to the monitor" do
    incident = uptime_incidents(:storefront_api_outage)
    mail = AlertsMailer.monitor_down(@user, incident)
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    since = incident.started_at.in_time_zone("Europe/London").strftime("%b %-d, %Y %H:%M %Z")

    assert_equal [ @user.email_address ], mail.to
    assert_equal "Down: Storefront API in storefront", mail.subject
    assert_includes html, "Storefront API is down"
    assert_includes html, "Good Sorcery couldn&#39;t reach api.storefront.example, even after an immediate retry."
    assert_includes html, "HTTP 503"
    assert_includes html, since
    assert_includes html, "Every 5 minutes"
    assert_includes html, "http://example.com/projects/storefront/uptime/#{incident.uptime_monitor_id}"
    assert_includes text, "Good Sorcery couldn't reach api.storefront.example, even after an immediate retry."
    assert_includes text, "Cause: HTTP 503"
    assert_includes text, "Since: #{since}"
    assert_not_includes html, "/health"
  end

  test "a recovered email says how long the monitor was down" do
    incident = uptime_incidents(:storefront_home_timeout)
    mail = AlertsMailer.monitor_recovered(@user, incident)
    text = mail.text_part.body.to_s

    assert_equal "Recovered: Storefront home in storefront after 14 min", mail.subject
    assert_includes mail.html_part.body.to_s, "Storefront home is back up"
    assert_includes text, "Good Sorcery reached storefront.example again."
    assert_includes text, "Down for: 14 min"
    assert_includes text, "Cause: Timed out after"
    assert_includes text, "From – To: #{incident.started_at.in_time_zone('Europe/London').strftime('%b %-d, %Y %H:%M %Z')} – "
  end

  test "uptime emails never contain the monitor URL's path or query" do
    monitor = uptime_monitors(:storefront_home)
    down = AlertsMailer.monitor_down(@user, monitor.incidents.create!(started_at: 3.minutes.ago, error_kind: "timeout"))
    recovered = AlertsMailer.monitor_recovered(@user, uptime_incidents(:storefront_home_timeout))

    [ down, recovered ].each do |mail|
      content = [ mail.subject, mail.html_part.body.to_s, mail.text_part.body.to_s, *mail.header_fields.map(&:to_s) ].join("\n")
      # The mute link carries its own ?token=; the monitor URL's path and query never appear.
      [ "uptime-fixture-secret", "token=uptime", "storefront.example/up" ].each { |secret| assert_not_includes content, secret }
      assert_includes content, "storefront.example"
    end
  end

  test "uptime emails carry a List-Unsubscribe link that mutes this app's uptime alerts" do
    mail = AlertsMailer.monitor_down(@user, uptime_incidents(:storefront_api_outage))
    url = mail["List-Unsubscribe"].value[/\A<(.+)>\z/, 1]

    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].value
    assert_includes mail.html_part.body.to_s, url
    assert_includes mail.text_part.body.to_s, "Mute storefront uptime alerts: #{url}"
    mute = AlertMute.find_by_token(Rack::Utils.parse_query(URI(url).query)["token"])
    assert_equal [ @user, @project, "uptime" ], [ mute.user, mute.project, mute.stream ]
  end

  test "escapes the monitor name in HTML" do
    uptime_monitors(:storefront_api).update_columns(name: "<b>API</b>")
    mail = AlertsMailer.monitor_down(@user, uptime_incidents(:storefront_api_outage))

    assert_includes mail.html_part.body.to_s, "&lt;b&gt;API&lt;/b&gt; is down"
    assert_not_includes mail.html_part.body.to_s, "<b>API</b>"
    assert_includes mail.text_part.body.to_s, "<b>API</b> is down"
  end

  test "checked at send time: down needs an open incident, recovered a resolved one" do
    assert_emails(0) { AlertsMailer.monitor_down(@user, uptime_incidents(:storefront_home_timeout)).deliver_now }
    assert_emails(0) { AlertsMailer.monitor_recovered(@user, uptime_incidents(:storefront_api_outage)).deliver_now }
  end

  test "uptime emails are checked at send time: nothing for muted, unverified or non-members" do
    incident = uptime_incidents(:storefront_api_outage)
    memberships(:jo_acme).update_notification_preference(@project, uptime_alerts_muted: true)

    assert_emails(0) { AlertsMailer.monitor_down(users(:jo), incident).deliver_now }
    assert_emails(0) { AlertsMailer.monitor_down(users(:outsider), incident).deliver_now }
    users(:alex).update_columns(email_verified_at: nil)
    assert_emails(0) { AlertsMailer.monitor_down(users(:alex), incident).deliver_now }
  end

  test "muting issue alerts doesn't stop uptime emails" do
    memberships(:alex_acme).update_notification_preference(@project, alerts_muted: true)

    assert_emails(1) { AlertsMailer.monitor_down(@user, uptime_incidents(:storefront_api_outage)).deliver_now }
  end

  test "slack_disabled tells an owner why Slack alerts stopped, never naming the webhook URL" do
    mail = slack_disabled_mail
    text = [ mail.subject, mail.html_part.body.to_s, mail.text_part.body.to_s, *mail.header_fields.map(&:to_s) ].join("\n")

    assert_equal [ @user.email_address ], mail.to
    assert_equal "Slack alerts for billing-api were turned off because Slack rejected the webhook", mail.subject
    assert_includes mail.text_part.body.to_s, "the channel no longer exists"
    assert_includes mail.html_part.body.to_s, "http://example.com/projects/billing-api/alerts"
    assert_not_includes text, "BillingRejectedSecret"
    assert_not_includes text, "hooks.slack.com"
  end

  test "slack_disabled goes to verified owners only, while the connection is still off" do
    assert_emails(0) { slack_disabled_mail(users(:jo)).deliver_now } # a member, not an owner
    assert_emails(0) { slack_disabled_mail(@user, projects(:storefront)).deliver_now } # connected

    users(:alex).update_columns(email_verified_at: nil)
    assert_emails(0) { slack_disabled_mail(users(:alex).reload).deliver_now }
  end

  private
    def slack_disabled_mail(user = @user, project = projects(:billing))
      AlertsMailer.slack_disabled(user, project)
    end

    def assert_no_captured_data(mail)
      content = [ mail.subject, mail.html_part.body.to_s, mail.text_part.body.to_s, *mail.header_fields.map(&:to_s) ].join("\n")
      CAPTURED.each { |text| assert_not_includes content, text }
    end
end
