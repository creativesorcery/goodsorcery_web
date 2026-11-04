require "test_helper"

class AlertDeliveryTest < ActiveSupport::TestCase
  setup do
    @user = users(:philip)
    @project = projects(:storefront)
    @issue = issues(:regressed)
  end

  test "record inserts once per user and key, and returns nil for a duplicate" do
    key = AlertDelivery.issue_key(:regression, @issue)

    id = AlertDelivery.record(user: @user, project: @project, kind: :regression, dedupe_key: key, issue: @issue)
    duplicate = AlertDelivery.record(user: @user, project: @project, kind: :regression, dedupe_key: key, issue: @issue)
    other_user = AlertDelivery.record(user: users(:jo), project: @project, kind: :regression, dedupe_key: key, issue: @issue)

    assert_kind_of Integer, id
    assert_nil duplicate
    assert_kind_of Integer, other_user
    delivery = AlertDelivery.find(id)
    assert delivery.regression?
    assert delivery.sent?
    assert_equal @issue, delivery.issue
  end

  test "issue keys: once per transition, still_happening once per window" do
    nomethod = issues(:nomethod)

    assert_equal "new_issue:#{nomethod.id}", AlertDelivery.issue_key(:new_issue, nomethod)
    assert_equal "reached_production:#{nomethod.id}", AlertDelivery.issue_key("reached_production", nomethod)
    assert_equal "regression:#{@issue.id}:#{@issue.regressed_at.to_i}", AlertDelivery.issue_key(:regression, @issue)

    now = Time.utc(2026, 10, 11, 7)
    same_window = AlertDelivery.issue_key(:still_happening, nomethod, at: now + 4.hours)
    assert_equal AlertDelivery.issue_key(:still_happening, nomethod, at: now), same_window
    assert_not_equal same_window, AlertDelivery.issue_key(:still_happening, nomethod, at: now + 6.hours)
  end

  test "a new regression after resolving gets a new key" do
    first = AlertDelivery.issue_key(:regression, @issue)
    @issue.regressed_at += 1.day

    assert_not_equal first, AlertDelivery.issue_key(:regression, @issue)
  end

  test "digest and summary keys" do
    assert_equal "daily_digest:#{@project.id}:2026-10-11", AlertDelivery.digest_key(@project, Date.new(2026, 10, 11))
    at = Time.utc(2026, 10, 11, 9, 59)
    assert_equal AlertDelivery.summary_key(at), AlertDelivery.summary_key(at - 59.minutes)
    assert_not_equal AlertDelivery.summary_key(at), AlertDelivery.summary_key(at + 1.minute)
  end

  test "incident keys: one down and one recovered email per incident" do
    incident = uptime_incidents(:storefront_api_outage)

    assert_equal "monitor_down:#{incident.id}", AlertDelivery.incident_key("monitor_down", incident)
    assert_equal "monitor_recovered:#{incident.id}", AlertDelivery.incident_key(:monitor_recovered, incident)
    assert_not_equal AlertDelivery.incident_key("monitor_down", incident),
                     AlertDelivery.incident_key("monitor_down", uptime_incidents(:storefront_home_timeout))
  end

  test "uptime alerts don't count towards the cap" do
    incident = uptime_incidents(:storefront_api_outage)
    AlertDelivery::HOURLY_CAP.times do |n|
      AlertDelivery.record(user: @user, project: @project, kind: :monitor_down, dedupe_key: "monitor_down:test-#{n}")
    end
    AlertDelivery.record(user: @user, project: @project, kind: :monitor_recovered, dedupe_key: AlertDelivery.incident_key(:monitor_recovered, incident))

    assert_equal 0, AlertDelivery.sent_in_last_hour(@user)
    assert_equal "sent", AlertDelivery.claim(user: @user, project: @project, kind: :new_issue, dedupe_key: "test")
  end

  test "the hourly cap counts sent emails in the last hour only" do
    assert_equal 0, AlertDelivery.sent_in_last_hour(@user), "the fixture is two hours old"

    (AlertDelivery::HOURLY_CAP - 1).times do |n|
      AlertDelivery.record(user: @user, project: @project, kind: :new_issue, dedupe_key: "test:#{n}")
    end
    AlertDelivery.record(user: @user, project: @project, kind: :new_issue, dedupe_key: "test:folded", status: :folded)
    assert_not AlertDelivery.cap_reached?(@user)

    AlertDelivery.record(user: @user, project: @project, kind: :new_issue, dedupe_key: "test:last")
    assert AlertDelivery.cap_reached?(@user)
    assert_not AlertDelivery.cap_reached?(users(:jo))
  end

  test "claim sends under the cap, folds at the cap, and skips a used key" do
    (AlertDelivery::HOURLY_CAP - 1).times do |n|
      assert_equal "sent", AlertDelivery.claim(user: @user, project: @project, kind: :new_issue, dedupe_key: "test:#{n}")
    end

    assert_equal "sent", AlertDelivery.claim(user: @user, project: @project, kind: :regression, issue: @issue, dedupe_key: "last")
    assert_equal "folded", AlertDelivery.claim(user: @user, project: @project, kind: :new_issue, dedupe_key: "over")
    assert_nil AlertDelivery.claim(user: @user, project: @project, kind: :new_issue, dedupe_key: "over")
    assert_equal "sent", AlertDelivery.claim(user: users(:jo), project: @project, kind: :new_issue, dedupe_key: "over")
  end

  test "digests and summaries don't count towards the cap" do
    AlertDelivery::HOURLY_CAP.times do |n|
      AlertDelivery.record(user: @user, project: @project, kind: :daily_digest, dedupe_key: "digest:#{n}")
    end
    AlertDelivery.record(user: @user, project: @project, kind: :summary, dedupe_key: AlertDelivery.summary_key)

    assert_equal 0, AlertDelivery.sent_in_last_hour(@user)
    assert_equal "sent", AlertDelivery.claim(user: @user, project: @project, kind: :new_issue, dedupe_key: "test")
  end

  test "folded deliveries await the summary until summarized" do
    AlertDelivery.record(user: @user, project: @project, kind: :new_issue, dedupe_key: "test:folded", status: :folded)

    assert_equal 1, AlertDelivery.where(user: @user).awaiting_summary.count
    AlertDelivery.where(user: @user).awaiting_summary.update_all(summarized_at: Time.current)
    assert_equal 0, AlertDelivery.where(user: @user).awaiting_summary.count
  end

  test "alerted_recently? looks at the issue and rule across recipients" do
    nomethod = issues(:nomethod)

    assert AlertDelivery.alerted_recently?(nomethod, :new_issue, within: 3.hours)
    assert_not AlertDelivery.alerted_recently?(nomethod, :new_issue, within: 1.hour)
    assert_not AlertDelivery.alerted_recently?(nomethod, :still_happening)
  end

  test "deleting the issue, app or user deletes its deliveries" do
    delivery = alert_deliveries(:philip_nomethod_new_issue)

    issues(:nomethod).destroy

    assert_not AlertDelivery.exists?(delivery.id)
  end
end
