# Posts one Slack alert (a SlackDelivery claimed by SlackIssueAlert,
# SlackUptimeAlert or SlackSummary) through SlackPost. The argument is the
# delivery's integer id only, never the webhook URL or captured data.
#
# A 429 is retried after Slack's Retry-After (capped by SlackWebhook); a 5xx
# or network error after BACKOFF; at most MAX_ATTEMPTS posts in all. Other
# answers are final. Logs carry the delivery id, kind, outcome and HTTP
# status or error class, never the URL.
class SlackPostJob < ApplicationJob
  queue_as :alerts

  MAX_ATTEMPTS = 5
  BACKOFF = [ 30.seconds, 2.minutes, 10.minutes, 30.minutes ].freeze

  def perform(slack_delivery_id)
    delivery = SlackDelivery.includes(:issue, project: :slack_connection, uptime_incident: { uptime_monitor: :project })
      .find_by(id: slack_delivery_id)
    result = delivery && SlackPost.new(delivery).deliver
    return unless result

    log(delivery, result)
    retry_later(result) if result.retry?
  end

  private
    def retry_later(result)
      return logger.warn("SlackPostJob gave up after #{executions} attempts") if executions >= MAX_ATTEMPTS

      retry_job(wait: result.retry_after&.seconds || BACKOFF.fetch(executions - 1, BACKOFF.last))
    end

    def log(delivery, result)
      logger.info("SlackPostJob delivery=#{delivery.id} kind=#{delivery.kind} outcome=#{result.outcome} status=#{result.log_label}")
    end
end
