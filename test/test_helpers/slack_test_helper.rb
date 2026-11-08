require_relative "uptime_test_helper"

# Support for Slack alert tests. Nothing here reaches Slack: jobs use a fake
# webhook, and SlackWebhook's own tests post to servers on 127.0.0.1
# (UptimeTestHelper::LocalHttpServer) through its `endpoint:` option.
#
#   with_fake_slack(slack_result(:delivered, 200)) { |slack| SlackPostJob.perform_now(id) }
#   slack.payloads   # => the payloads posted, in order
#   slack.urls       # => the webhook URL each was posted to
module SlackTestHelper
  include UptimeTestHelper

  SLACK_SECRET = "SlackFixtureSecret".freeze
  WEBHOOK_URL = "https://hooks.slack.com/services/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6789".freeze

  # Returns its results in order from #post and records what was posted.
  class FakeWebhook
    attr_reader :payloads, :urls

    def initialize(results)
      @results = results.dup
      @payloads = []
      @urls = []
    end

    def for_url(url)
      @urls << url
      self
    end

    def post(payload)
      @payloads << payload
      @results.shift || raise("FakeWebhook has no results left")
    end
  end

  def slack_result(outcome, http_status = nil, reason: nil, retry_after: nil)
    SlackWebhook::Result.of(outcome, http_status:, reason:, retry_after:)
  end

  # Every SlackWebhook.new inside the block returns one FakeWebhook.
  def with_fake_slack(*results)
    fake = FakeWebhook.new(results)
    SlackWebhook.singleton_class.define_method(:new) { |url, **| fake.for_url(url) }
    yield fake
  ensure
    SlackWebhook.singleton_class.remove_method(:new)
  end

  # All the text a payload would show, for content assertions.
  def slack_text(payload) = JSON.generate(payload)
end
