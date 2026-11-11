require "test_helper"

# alex's zone is Europe/London (BST, UTC+1, until 2026-10-25 01:00 UTC);
# jo's is UTC.
class DailyDigestTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  SUMMER_MORNING = Time.utc(2026, 7, 15, 8) # 09:00 in London, 08:00 UTC

  setup do
    travel_to SUMMER_MORNING
    @project = projects(:storefront)
    @project.alert_rules.find_by!(kind: "daily_digest").update!(enabled: true)
    reset_activity
    seen(issues(:nomethod), events: 12)
  end

  test "mails each recipient in the 09:00 hour of their own time zone" do
    assert_equal [ users(:alex) ], deliver

    travel_to SUMMER_MORNING + 1.hour
    assert_equal [ users(:jo) ], deliver
  end

  test "a zone with a half-hour offset gets it on the hourly run inside its 09:00 hour" do
    users(:jo).update!(time_zone: "Asia/Kolkata") # UTC+5:30
    travel_to Time.utc(2026, 7, 15, 4) # 09:30 in Kolkata
    seen(issues(:nomethod), events: 3)

    assert_equal [ users(:jo) ], deliver
  end

  test "a repeated or late run sends nothing twice the same local day" do
    assert_equal [ users(:alex) ], deliver

    travel 59.minutes
    assert_empty deliver
    assert_equal 1, AlertDelivery.where(user: users(:alex), kind: "daily_digest").count
  end

  test "DST changes neither skip nor double a day: one digest per local date" do
    users(:jo).update!(time_zone: "America/Los_Angeles")
    travel_to Time.utc(2026, 10, 24, 8) # Saturday 09:00 BST
    seen(issues(:nomethod), events: 5)
    assert_equal [ users(:alex) ], deliver

    travel_to Time.utc(2026, 10, 25, 8) # clocks went back: 08:00 GMT
    seen(issues(:nomethod), events: 5)
    assert_empty deliver
    travel_to Time.utc(2026, 10, 25, 9) # 09:00 GMT, the next local date
    assert_equal [ users(:alex) ], deliver
    travel_to Time.utc(2026, 10, 25, 9, 40)
    assert_empty deliver

    keys = AlertDelivery.where(user: users(:alex), kind: "daily_digest").pluck(:dedupe_key)
    assert_equal [ "2026-10-24", "2026-10-25" ], keys.map { |key| key.split(":").last }.sort
  end

  test "nothing is sent or recorded when no open issue had events in the last 24 hours" do
    reset_activity
    seen(issues(:ignored_issue), events: 50)
    seen(issues(:resolved_issue), events: 50)

    assert_no_enqueued_emails { assert_empty deliver }
    assert_not AlertDelivery.exists?(kind: "daily_digest")
  end

  test "lists open issues in scope, busiest first" do
    seen(issues(:regressed), events: 40)
    seen(issues(:card_error), events: 7)
    seen(issues(:ignored_issue), events: 90)
    digest = DailyDigest.new(@project)

    assert_equal [ issues(:regressed), issues(:nomethod), issues(:card_error) ], digest.issues
    assert_equal [ 40, 12, 7 ], digest.issues.map(&:recent_events)
    assert_equal 3, digest.issue_count
    assert_equal 0, digest.more_count
  end

  test "follows the app's environment scope" do
    seen(issues(:regressed), events: 40) # production and staging
    @project.update!(alert_scope: "selected", alert_selected_environments: [ "staging" ])

    assert_equal [ issues(:regressed) ], DailyDigest.new(@project).issues
  end

  test "caps the list and counts the rest" do
    stub_const(DailyDigest, :LISTED, 1) do
      seen(issues(:regressed), events: 40)
      digest = DailyDigest.new(@project)

      assert_equal [ issues(:regressed) ], digest.issues
      assert_equal 1, digest.more_count
    end
  end

  test "leaves out members who turned the app's digest off, unverified members and outsiders" do
    travel_to SUMMER_MORNING + 1.hour # jo's 09:00
    seen(issues(:nomethod), events: 1)
    memberships(:jo_acme).update_notification_preference(@project, digest_enabled: false)
    assert_empty deliver

    memberships(:jo_acme).update_notification_preference(@project, digest_enabled: true, alerts_muted: true)
    assert_equal [ users(:jo) ], DailyDigest.new(@project).due_recipients, "muting alerts keeps the digest"

    users(:jo).update_columns(email_verified_at: nil)
    users(:outsider).update_columns(time_zone: "UTC")
    assert_empty DailyDigest.new(@project).due_recipients
  end

  test "deliver_due covers only apps with the digest rule on" do
    billing = projects(:billing)
    seen(issues(:billing_timeout), events: 4)

    assert_enqueued_email_with AlertsMailer, :digest, args: [ users(:alex), @project ] do
      DailyDigest.deliver_due
    end
    assert_not AlertDelivery.exists?(project: billing, kind: "daily_digest")
  end

  private
    def deliver = DailyDigest.new(@project).deliver

    def reset_activity
      IssueHourlyCount.delete_all
      Issue.update_all(last_seen_at: 10.days.ago)
    end

    def seen(issue, events:)
      issue.update_columns(last_seen_at: 1.hour.ago)
      IssueHourlyCount.upsert({ issue_id: issue.id, hour: 1.hour.ago.beginning_of_hour, count: events }, record_timestamps: false)
    end

    def stub_const(klass, name, value)
      original = klass.const_get(name)
      klass.send(:remove_const, name)
      klass.const_set(name, value)
      yield
    ensure
      klass.send(:remove_const, name)
      klass.const_set(name, original)
    end
end
