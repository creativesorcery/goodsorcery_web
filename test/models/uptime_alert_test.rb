require "test_helper"

class UptimeAlertTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @project = projects(:storefront)
    @incident = uptime_incidents(:storefront_api_outage) # open
  end

  test "a down alert mails every verified member who hasn't muted uptime alerts, never an outsider" do
    recipients = nil
    assert_enqueued_emails 2 do
      recipients = UptimeAlert.new(@incident, "monitor_down").deliver
    end

    assert_equal [ users(:jo), users(:philip) ].sort_by(&:id), recipients.sort_by(&:id)
    assert_enqueued_email_with AlertsMailer, :monitor_down, args: [ users(:philip), @incident ]
    deliveries = AlertDelivery.where(dedupe_key: "monitor_down:#{@incident.id}")
    assert_equal [ [ "monitor_down", "sent", nil ] ] * 2, deliveries.pluck(:kind, :status, :issue_id)
  end

  test "one email per incident and kind: a repeated delivery mails nobody" do
    UptimeAlert.new(@incident, "monitor_down").deliver

    assert_no_enqueued_emails { assert_empty UptimeAlert.new(@incident, "monitor_down").deliver }
  end

  test "a new incident of the same monitor alerts again" do
    UptimeAlert.new(@incident, "monitor_down").deliver
    @incident.update_columns(resolved_at: Time.current)
    second = @incident.uptime_monitor.incidents.create!(started_at: Time.current, error_kind: "timeout")

    assert_equal 2, UptimeAlert.new(second, "monitor_down").deliver.size
  end

  test "a recovered email goes only to the people who were sent the down email" do
    memberships(:jo_acme).update_notification_preference(@project, uptime_alerts_muted: true)
    UptimeAlert.new(@incident, "monitor_down").deliver
    memberships(:jo_acme).update_notification_preference(@project, uptime_alerts_muted: false)
    @incident.update_columns(resolved_at: Time.current)

    assert_enqueued_emails 1 do
      assert_equal [ users(:philip) ], UptimeAlert.new(@incident, "monitor_recovered").deliver
    end
    assert_enqueued_email_with AlertsMailer, :monitor_recovered, args: [ users(:philip), @incident ]
    assert_empty UptimeAlert.new(@incident, "monitor_recovered").deliver, "once per incident"
  end

  test "no recovered email without any down email" do
    resolved = uptime_incidents(:storefront_home_timeout)

    assert UptimeAlert.new(resolved, "monitor_recovered").due?
    assert_no_enqueued_emails { assert_empty UptimeAlert.new(resolved, "monitor_recovered").deliver }
  end

  test "a down alert needs the incident still open, a recovered alert needs it resolved" do
    assert UptimeAlert.new(@incident, "monitor_down").due?
    assert_not UptimeAlert.new(@incident, "monitor_recovered").due?

    @incident.update_columns(resolved_at: Time.current)
    assert_not UptimeAlert.new(@incident, "monitor_down").due?
    assert_no_enqueued_emails { assert_empty UptimeAlert.new(@incident, "monitor_down").deliver }
  end

  test "nothing when the app's rule is off" do
    alert_rules(:storefront_monitor_down).update!(enabled: false)

    assert_not UptimeAlert.new(@incident, "monitor_down").due?
    assert_no_enqueued_emails { assert_empty UptimeAlert.new(@incident, "monitor_down").deliver }
  end

  test "an unknown kind is never due" do
    assert_not UptimeAlert.new(@incident, "new_issue").due?
  end

  test "the environment scope doesn't apply" do
    @project.update!(alert_scope: "selected", alert_selected_environments: [ "staging" ])

    assert UptimeAlert.new(@incident, "monitor_down").due?
  end

  test "muted uptime alerts send nothing, while issue alerts still flow" do
    memberships(:philip_acme).update_notification_preference(@project, uptime_alerts_muted: true)

    assert_equal [ users(:jo) ], UptimeAlert.new(@incident, "monitor_down").deliver
    assert_includes IssueAlert.new(issues(:regressed), "regression").deliver, users(:philip)
  end

  test "muted issue alerts still let uptime alerts through" do
    memberships(:philip_acme).update_notification_preference(@project, alerts_muted: true)

    assert_not_includes IssueAlert.new(issues(:regressed), "regression").deliver, users(:philip)
    assert_includes UptimeAlert.new(@incident, "monitor_down").deliver, users(:philip)
  end

  test "unverified members are never mailed" do
    users(:jo).update_columns(email_verified_at: nil)

    assert_equal [ users(:philip) ], UptimeAlert.new(@incident, "monitor_down").deliver
  end

  test "a user at the hourly cap still gets the down alert, and it is never folded or summarised" do
    AlertDelivery::HOURLY_CAP.times do |n|
      AlertDelivery.record(user: users(:philip), project: @project, kind: :new_issue, dedupe_key: "test:#{n}")
    end
    assert AlertDelivery.cap_reached?(users(:philip))

    assert_enqueued_email_with AlertsMailer, :monitor_down, args: [ users(:philip), @incident ] do
      assert_includes UptimeAlert.new(@incident, "monitor_down").deliver, users(:philip)
    end
    delivery = AlertDelivery.find_by!(user: users(:philip), dedupe_key: "monitor_down:#{@incident.id}")
    assert_predicate delivery, :sent?
    assert_equal AlertDelivery::HOURLY_CAP, AlertDelivery.sent_in_last_hour(users(:philip)), "uptime rows don't move the count"
  end

  test "uptime alerts are never part of the hourly summary" do
    UptimeAlert.new(@incident, "monitor_down").deliver

    travel 1.hour do
      assert_nil AlertSummary.new(users(:philip)).deliver
    end
    assert_empty AlertDelivery.awaiting_summary.where(kind: AlertRule::UPTIME_KINDS)
  end
end
