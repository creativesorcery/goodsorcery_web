require "test_helper"

class SlackDeliveryTest < ActiveSupport::TestCase
  setup do
    @project = projects(:storefront)
    @issue = issues(:regressed)
  end

  test "keys are AlertDelivery's own, prefixed for Slack" do
    freeze_time

    assert_equal "slack:new_issue:#{@issue.id}", SlackDelivery.dedupe_key(:new_issue, @issue)
    assert_equal "slack:#{AlertDelivery.issue_key(:regression, @issue)}", SlackDelivery.dedupe_key(:regression, @issue)
    assert_equal "slack:#{AlertDelivery.issue_key(:still_happening, @issue)}", SlackDelivery.dedupe_key(:still_happening, @issue)
    incident = uptime_incidents(:storefront_api_outage)
    assert_equal "slack:monitor_down:#{incident.id}", SlackDelivery.dedupe_key(:monitor_down, incident)
    assert_equal "slack:#{AlertDelivery.summary_key}", SlackDelivery.dedupe_key(:summary, nil)
  end

  test "record inserts once per key and app" do
    first = SlackDelivery.record(project: @project, kind: :regression, issue: @issue)

    assert first.persisted?
    assert_nil SlackDelivery.record(project: @project, kind: :regression, issue: @issue)
  end

  test "claim sends up to the hourly cap per app, then folds; other apps are unaffected" do
    freeze_time
    (SlackDelivery::HOURLY_CAP - 1).times do |n|
      SlackDelivery.insert({ project_id: @project.id, kind: "new_issue", dedupe_key: "slack:cap-#{n}", status: "sent", created_at: Time.current })
    end

    assert_predicate SlackDelivery.claim(project: @project, kind: :regression, issue: @issue), :sent?
    assert_predicate SlackDelivery.claim(project: @project, kind: :new_issue, issue: issues(:card_error)), :folded?
    assert_nil SlackDelivery.claim(project: @project, kind: :new_issue, issue: issues(:card_error))
    assert_predicate SlackDelivery.claim(project: projects(:billing), kind: :new_issue, issue: issues(:billing_timeout)), :sent?

    travel 1.hour + 1.second
    assert_predicate SlackDelivery.claim(project: @project, kind: :new_issue, issue: issues(:resolved_issue)), :sent?
  end

  test "mark_posted stamps once" do
    delivery = SlackDelivery.record(project: @project, kind: :regression, issue: @issue)

    assert delivery.mark_posted
    assert_not delivery.mark_posted
    assert_predicate delivery.reload, :posted?
  end

  test "old rows are pruned with alert deliveries, except an open incident's down post" do
    old = 31.days.ago
    SlackDelivery.update_all(created_at: old)
    down = SlackDelivery.record(project: @project, kind: :monitor_down, uptime_incident: uptime_incidents(:storefront_api_outage), at: old)
    closed = SlackDelivery.record(project: @project, kind: :monitor_down, uptime_incident: uptime_incidents(:storefront_home_timeout), at: old)

    Ingest::Retention.new.prune_alert_deliveries

    assert_equal [ down.id ], SlackDelivery.pluck(:id)
    assert_not SlackDelivery.exists?(closed.id)
  end
end
