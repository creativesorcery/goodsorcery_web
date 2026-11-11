require "test_helper"

class AlertSummaryTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    travel_to Time.utc(2026, 10, 14, 10, 30)
    # The fixture is stamped from the real clock; keep it in this test's past
    # so it never counts towards the frozen hour's cap.
    alert_deliveries(:alex_nomethod_new_issue).update_columns(created_at: 2.hours.ago)
    @user = users(:alex)
    @storefront = projects(:storefront)
    @billing = projects(:billing)
  end

  test "alerts over the cap are folded, then summarized in one email after the hour" do
    AlertDelivery::HOURLY_CAP.times { |n| claim(@storefront, "sent:#{n}") }
    assert_equal "folded", claim(@storefront, "over:1", kind: :regression)
    assert_equal "folded", claim(@billing, "over:2")
    assert_equal "folded", claim(@billing, "over:3")

    travel_to Time.utc(2026, 10, 14, 11, 2)
    counts = nil
    assert_enqueued_emails 1 do
      counts = AlertSummary.new(@user).deliver
    end

    expected = { @storefront.id.to_s => { "regression" => 1 }, @billing.id.to_s => { "new_issue" => 2 } }
    assert_equal expected, counts
    assert_enqueued_email_with AlertsMailer, :summary, args: [ @user, expected ]
    assert_equal 0, AlertDelivery.where(user: @user).awaiting_summary.count
    assert_equal 1, AlertDelivery.where(user: @user, kind: "summary").count
  end

  test "folded alerts of the current hour wait for the next run" do
    claim(@storefront, "over", status: "folded")

    assert_no_enqueued_emails { assert_nil AlertSummary.new(@user).deliver }
    assert_equal 1, AlertDelivery.where(user: @user).awaiting_summary.count
  end

  test "one summary per user per hour, even when the run repeats" do
    claim(@storefront, "over:1", status: "folded")
    travel 1.hour

    assert AlertSummary.new(@user).deliver
    claim(@storefront, "over:2", status: "folded", at: 1.hour.ago)
    assert_no_enqueued_emails { assert_nil AlertSummary.new(@user).deliver }
    assert_equal 1, AlertDelivery.where(user: @user, kind: "summary").count
    assert_equal 1, AlertDelivery.where(user: @user).awaiting_summary.count, "left for next hour's summary"
  end

  test "deliver_due summarizes every user with folded alerts from before this hour" do
    claim(@storefront, "alex", status: "folded")
    AlertDelivery.record(user: users(:jo), project: @storefront, kind: :new_issue, dedupe_key: "jo", status: "folded")
    travel 1.hour

    assert_enqueued_emails(2) { AlertSummary.deliver_due }
    assert_not AlertDelivery.awaiting_summary.exists?
  end

  test "the mail job gets ids, kinds and numbers only" do
    claim(@storefront, "over", status: "folded")
    travel 1.hour
    AlertSummary.new(@user).deliver

    job = enqueued_jobs.find { |queued| queued["job_class"] == "ActionMailer::MailDeliveryJob" }
    arguments = job["arguments"].to_json
    assert_includes arguments, @storefront.id.to_s
    [ @storefront.name, issues(:nomethod).message, @user.email_address ].each { |text| assert_not_includes arguments, text }
  end

  private
    def claim(project, key, kind: :new_issue, status: nil, at: nil)
      return AlertDelivery.claim(user: @user, project:, kind:, dedupe_key: key) unless status

      travel_to(at || Time.current) do
        AlertDelivery.record(user: @user, project:, kind:, dedupe_key: key, status:)
      end
      status
    end
end
