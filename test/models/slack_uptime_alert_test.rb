require "test_helper"

class SlackUptimeAlertTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = projects(:storefront)
    @open = uptime_incidents(:storefront_api_outage)
    @resolved = uptime_incidents(:storefront_home_timeout)
  end

  test "posts a down alert once per incident, with the delivery id only" do
    delivery = nil
    assert_enqueued_jobs(1, only: SlackPostJob) { delivery = SlackUptimeAlert.new(@open, "monitor_down").post_later }

    assert_equal [ @open.id, "slack:monitor_down:#{@open.id}", "sent" ], delivery.values_at(:uptime_incident_id, :dedupe_key, :status)
    assert_enqueued_with job: SlackPostJob, args: [ delivery.id ]
    assert_nil SlackUptimeAlert.new(@open, "monitor_down").post_later
  end

  test "down needs an open incident, recovered a resolved one" do
    assert_nil SlackUptimeAlert.new(@resolved, "monitor_down").post_later
    assert_nil SlackUptimeAlert.new(@open, "monitor_recovered").post_later
  end

  test "recovered posts only after this incident's down post, unless the down rule is off" do
    assert_nil SlackUptimeAlert.new(@resolved, "monitor_recovered").post_later

    SlackDelivery.record(project: @project, kind: :monitor_down, uptime_incident: @resolved)
    assert SlackUptimeAlert.new(@resolved, "monitor_recovered").post_later

    SlackDelivery.where(kind: "monitor_recovered").delete_all
    SlackDelivery.where(kind: "monitor_down").delete_all
    @project.alert_rules.find_by!(kind: "monitor_down").update!(enabled: false)
    assert SlackUptimeAlert.new(UptimeIncident.find(@resolved.id), "monitor_recovered").post_later
  end

  test "posts nothing while the rule or the connection is off" do
    @project.alert_rules.find_by!(kind: "monitor_down").update!(enabled: false)
    assert_nil SlackUptimeAlert.new(@open, "monitor_down").post_later

    @project.alert_rules.find_by!(kind: "monitor_down").update!(enabled: true)
    slack_connections(:storefront).update!(enabled: false)
    assert_nil SlackUptimeAlert.new(UptimeIncident.find(@open.id), "monitor_down").post_later
  end

  test "uptime posts skip the hourly cap and never count towards it" do
    freeze_time
    SlackDelivery::HOURLY_CAP.times do |n|
      SlackDelivery.insert({ project_id: @project.id, kind: "new_issue", dedupe_key: "slack:cap-#{n}", status: "sent", created_at: Time.current })
    end

    assert_predicate SlackUptimeAlert.new(@open, "monitor_down").post_later, :sent?
    assert_equal SlackDelivery::HOURLY_CAP, SlackDelivery.sent_in_last_hour(@project)
  end

  test "ignores the environment scope" do
    @project.update!(alert_scope: "selected", alert_selected_environments: [ "staging" ])

    assert SlackUptimeAlert.new(@open, "monitor_down").post_later
  end
end
