require "test_helper"

class AlertsMailerTest < ActionMailer::TestCase
  # Captured data in the nomethod occurrence fixtures (locals, params,
  # headers, session, user, breadcrumbs, context, tags): none of it may
  # appear in an alert email. Only the issue's redacted summary columns may.
  CAPTURED = [ "mara@example.com", "Mara Lindqvist", "5521", "81.2.69.160", "FALL25", "CartItem", "variant_id",
               "Mobile Safari", "iPhone", "shop.acme.dev", "web-7f9c-2", "taxjar", "discontinued variant", "puma",
               "a1b2c3d", "88123" ].freeze

  setup do
    @user = users(:philip) # Europe/London
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
    memberships(:philip_acme).update_notification_preference(@project, digest_enabled: false)
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

  private
    def assert_no_captured_data(mail)
      content = [ mail.subject, mail.html_part.body.to_s, mail.text_part.body.to_s, *mail.header_fields.map(&:to_s) ].join("\n")
      CAPTURED.each { |text| assert_not_includes content, text }
    end
end
