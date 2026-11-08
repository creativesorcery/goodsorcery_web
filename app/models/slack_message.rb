# One Slack message as a Block Kit payload plus a plain `text` fallback (used
# in notifications and by clients that can't show blocks), docs/ARCHITECTURE.md
# §11.5. Subclasses: IssueAlert, UptimeAlert, Summary and TestMessage.
#
#   SlackMessage::IssueAlert.new(issue, "regression").payload
#   # => { text: "Regression in storefront: …", blocks: [ … ] }
#
# Content rule (as for alert emails, but stricter): the kind, the app's name,
# an issue's redacted title (message, else exception class), environment
# names, counts, times and links, or a monitor's name, host and cause. Never
# occurrence payloads, params, headers, backtraces, user identities, a
# monitor's URL or the webhook URL. Every dynamic string goes through
# #escape (&, <, >), so nothing can form a Slack link, mention or
# <!channel>; mrkdwn text objects are `verbatim` so Slack doesn't auto-link.
# Links use the instance's public URL (GOODSORCERY_PUBLIC_URL, through the
# mailer's default_url_options).
class SlackMessage
  include Rails.application.routes.url_helpers

  TITLE_LENGTH = 300
  TEXT_LENGTH = 400

  def payload
    { text: fallback_text.truncate(TEXT_LENGTH), blocks: }
  end

  def self.escape(text)
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end

  private
    def default_url_options = Rails.application.config.action_mailer.default_url_options || {}

    def escape(text) = self.class.escape(text)

    def kind_label(kind) = AlertsHelper::RULE_COPY.fetch(kind.to_s).first

    def mrkdwn(text) = { type: "mrkdwn", text:, verbatim: true }

    def section(text) = { type: "section", text: mrkdwn(text) }

    # A two-column grid of "*Label*\nvalue" pairs (values already escaped).
    def fields(pairs)
      { type: "section", fields: pairs.map { |label, value| mrkdwn("*#{label}*\n#{value}") } }
    end

    def button(label, url)
      { type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: label.truncate(75) }, url: } ] }
    end

    # Slack shows it in each reader's own zone; the fallback is UTC.
    def slack_time(time)
      return "—" unless time

      "<!date^#{time.to_i}^{date_short_pretty} {time}|#{time.utc.strftime('%b %-d, %Y %H:%M UTC')}>"
    end

    def count(number, noun) = "#{number.to_i.to_fs(:delimited)} #{noun.pluralize(number.to_i)}"
end
