require "test_helper"
require_relative "../test_helpers/slack_test_helper"

class SlackMessageTest < ActiveSupport::TestCase
  include SlackTestHelper

  # Strings from the fixture occurrence payloads (user, params, headers,
  # breadcrumbs, context, backtrace) and the monitor's secret URL.
  CAPTURED = [ "mara@example.com", "Mara Lindqvist", "FALL25", "Mobile Safari", "taxjar", "web-7f9c-2", "cart_total.rb",
               "CheckoutsController", "81.2.69.160", "uptime-fixture-secret", "/up?token" ].freeze

  setup do
    @issue = issues(:nomethod)
    travel_to @issue.last_seen_at + 1.minute
  end

  test "an issue alert: kind, app, redacted title, environments, counts, times and a link" do
    payload = SlackMessage::IssueAlert.new(@issue, "new_issue").payload
    text = slack_text(payload)

    assert_equal "New issue in storefront: undefined method `price_cents' for nil", payload[:text]
    assert_equal "*New issue* in *storefront*\nundefined method `price_cents' for nil", payload[:blocks].first.dig(:text, :text)
    assert_includes text, "*Environments*\\nproduction"
    assert_includes text, "1,284 events · 212 users"
    assert_includes text, "<!date^#{@issue.first_seen_at.to_i}^{date_short_pretty} {time}|"
    button = payload[:blocks].last[:elements].sole
    assert_equal "Open GS-1042", button.dig(:text, :text)
    assert_equal "http://example.com/projects/storefront/issues/GS-1042", button[:url]
  end

  test "never carries captured data, the monitor URL or the webhook URL" do
    payloads = [ SlackMessage::IssueAlert.new(@issue, "regression").payload,
                 SlackMessage::IssueAlert.new(@issue, "still_happening").payload,
                 SlackMessage::UptimeAlert.new(uptime_incidents(:storefront_api_outage), "monitor_down").payload,
                 SlackMessage::UptimeAlert.new(uptime_incidents(:storefront_home_timeout), "monitor_recovered").payload,
                 SlackMessage::Summary.new(projects(:storefront), { "new_issue" => 3 }).payload,
                 SlackMessage::TestMessage.new(projects(:storefront)).payload ]

    payloads.map { |payload| slack_text(payload) }.each do |text|
      CAPTURED.each { |secret| assert_not_includes text, secret }
      assert_not_includes text, SLACK_SECRET
    end
  end

  test "escapes &, < and > in every dynamic string, so nothing becomes a link or a mention" do
    projects(:storefront).update_columns(name: "shop & <b>co</b>")
    @issue.update_columns(message: "<!channel> <https://evil.example|click> & <@U123>", environments: [ "prod<uction>" ])

    payload = SlackMessage::IssueAlert.new(@issue.reload, "new_issue").payload
    text = slack_text(payload)

    assert_includes payload[:blocks].first.dig(:text, :text), "&lt;!channel&gt; &lt;https://evil.example|click&gt; &amp; &lt;@U123&gt;"
    assert_includes payload[:text], "shop &amp; &lt;b&gt;co&lt;/b&gt;"
    assert_includes text, "prod&lt;uction&gt;"
    assert_not_includes text, "<!channel>"
    assert_not_includes text, "<https://evil"
    assert(payload[:blocks].flat_map { |block| [ block[:text], *block[:fields] ] }.compact.all? { |object| object[:verbatim] })
  end

  test "falls back to the exception class without a message, and truncates long titles" do
    @issue.update_columns(message: "")
    assert_includes SlackMessage::IssueAlert.new(@issue, "new_issue").payload[:text], ": NoMethodError"

    @issue.update_columns(message: "x" * 5_000)
    payload = SlackMessage::IssueAlert.new(@issue, "new_issue").payload
    assert_operator payload[:text].length, :<=, SlackMessage::TEXT_LENGTH
    assert_operator payload[:blocks].first.dig(:text, :text).length, :<, 400
  end

  test "still happening shows the last hour against the threshold" do
    IssueHourlyCount.delete_all
    IssueHourlyCount.create!(issue: @issue, hour: Time.current.beginning_of_hour, count: 140)

    text = slack_text(SlackMessage::IssueAlert.new(@issue, "still_happening").payload)

    assert_includes text, "*Last hour*\\n140 events (threshold 100)"
  end

  test "monitor down and recovered name the monitor and host only" do
    down = SlackMessage::UptimeAlert.new(uptime_incidents(:storefront_api_outage), "monitor_down").payload
    recovered = SlackMessage::UptimeAlert.new(uptime_incidents(:storefront_home_timeout), "monitor_recovered").payload

    assert_equal "Down: Storefront API in storefront", down[:text]
    assert_includes slack_text(down), "couldn't reach api.storefront.example"
    assert_equal "http://example.com/projects/storefront/uptime/#{uptime_monitors(:storefront_api).id}",
                 down[:blocks].last[:elements].sole[:url]
    assert_equal "Recovered: Storefront home in storefront after 14 min", recovered[:text]
    assert_includes slack_text(recovered), "*Host*\\nstorefront.example"
  end

  test "the summary counts folded alerts per kind" do
    payload = SlackMessage::Summary.new(projects(:storefront), { "regression" => 1, "new_issue" => 3 }).payload

    assert_equal "And 4 more alerts in storefront in the last hour", payload[:text]
    assert_includes payload[:blocks].first.dig(:text, :text), "New issue: 3 · Regression: 1"
    assert_equal "http://example.com/projects/storefront/issues", payload[:blocks].last[:elements].sole[:url]
  end

  test "the test message links to the app's alert settings" do
    payload = SlackMessage::TestMessage.new(projects(:storefront)).payload

    assert_includes payload[:text], "Good Sorcery is connected"
    assert_equal "http://example.com/projects/storefront/alerts", payload[:blocks].last[:elements].sole[:url]
  end
end
