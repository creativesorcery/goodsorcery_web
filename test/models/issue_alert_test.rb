require "test_helper"

class IssueAlertTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @project = projects(:storefront)
    @issue = issues(:regressed)
  end

  test "transitions come from what the counter UPDATE returned" do
    issue = Issue.new
    issue.define_singleton_method(:previous_status) { "unresolved" }
    issue.define_singleton_method(:just_reached_production) { false }

    assert_equal [ "new_issue" ], IssueAlert.transitions(issue, created: true)
    assert_empty IssueAlert.transitions(issue, created: false)

    issue.define_singleton_method(:previous_status) { "resolved" }
    issue.define_singleton_method(:just_reached_production) { true }
    assert_equal %w[regression reached_production], IssueAlert.transitions(issue, created: false)
  end

  test "mails every verified member of the app's account who hasn't muted it, never an outsider" do
    recipients = nil
    assert_enqueued_emails 2 do
      recipients = IssueAlert.new(@issue, "regression").deliver
    end

    assert_equal [ users(:jo), users(:alex) ].sort_by(&:id), recipients.sort_by(&:id)
    assert_not_includes recipients, users(:outsider)
    assert_enqueued_email_with AlertsMailer, :issue_alert, args: [ users(:alex), @issue, "regression" ]
    assert_equal 2, AlertDelivery.where(issue: @issue, kind: "regression", status: "sent").count
  end

  test "sends once per transition: a second delivery mails nobody" do
    IssueAlert.new(@issue, "regression").deliver

    assert_no_enqueued_emails { assert_empty IssueAlert.new(@issue, "regression").deliver }
  end

  test "a new regression after resolving again alerts again" do
    IssueAlert.new(@issue, "regression").deliver
    @issue.update_columns(regressed_at: 1.minute.from_now)

    assert_equal 2, IssueAlert.new(@issue, "regression").deliver.size
  end

  test "members who muted the app are left out" do
    issue = issues(:billing_timeout) # jo muted billing-api (fixture)

    assert_equal [ users(:alex) ], IssueAlert.new(issue, "new_issue").deliver
  end

  test "members whose email isn't verified are never mailed" do
    users(:jo).update_columns(email_verified_at: nil)

    assert_equal [ users(:alex) ], IssueAlert.new(@issue, "regression").deliver
  end

  test "an earlier delivery of the same key is skipped (alex got this new_issue alert)" do
    issue = issues(:nomethod)

    assert_equal [ users(:jo) ], IssueAlert.new(issue, "new_issue").deliver
  end

  test "nothing when the rule is off" do
    @project.alert_rules.find_by!(kind: "regression").update!(enabled: false)

    assert_not IssueAlert.new(@issue, "regression").due?
    assert_no_enqueued_emails { assert_empty IssueAlert.new(@issue, "regression").deliver }
  end

  test "resolved and ignored issues never alert" do
    assert_not IssueAlert.new(issues(:resolved_issue), "regression").due?
    assert_not IssueAlert.new(issues(:ignored_issue), "still_happening").due?

    @issue.update_columns(status: "ignored")
    assert_no_enqueued_emails { assert_empty IssueAlert.new(@issue, "regression").deliver }
  end

  test "the environment scope is checked against the triggering occurrence's environment" do
    @project.update!(alert_scope: "selected", alert_selected_environments: [ "staging" ])
    production = occurrences(:regressed_latest)

    assert_not IssueAlert.new(@issue, "regression", occurrence_id: production.id).due?

    production.update_columns(environment: "staging")
    assert IssueAlert.new(@issue, "regression", occurrence_id: production.id).due?
  end

  test "without an occurrence, any of the issue's environments counts" do
    @project.update!(alert_scope: "selected", alert_selected_environments: [ "staging" ])
    assert IssueAlert.new(@issue, "still_happening").due?, "regressed is seen in production and staging"

    assert_not IssueAlert.new(issues(:nomethod), "still_happening").due?, "nomethod is production only"
  end

  test "the default scope follows the app's default environment" do
    @project.update!(default_environment: "staging")
    assert_not IssueAlert.new(issues(:nomethod), "new_issue").due?

    @project.update!(default_environment: nil)
    assert IssueAlert.new(issues(:nomethod).reload, "still_happening").due?
  end

  test "still_happening alerts at most once per issue per 6 hours" do
    alert = IssueAlert.new(@issue, "still_happening")
    assert_equal 2, alert.deliver.size

    travel 5.hours do
      assert_not IssueAlert.new(@issue, "still_happening").due?
    end
    travel 6.hours + 1.minute do
      assert_equal 2, IssueAlert.new(@issue, "still_happening").deliver.size
    end
  end

  test "over the hourly cap the alert is folded for the summary, not mailed" do
    AlertDelivery::HOURLY_CAP.times do |n|
      AlertDelivery.record(user: users(:alex), project: @project, kind: :new_issue, dedupe_key: "test:#{n}")
    end

    assert_enqueued_emails 1 do
      assert_equal [ users(:jo) ], IssueAlert.new(@issue, "regression").deliver
    end
    folded = AlertDelivery.find_by!(user: users(:alex), issue: @issue, kind: "regression")
    assert_predicate folded, :folded?
    assert_nil folded.summarized_at
  end
end
