# new_issue, regression, reached_production or still_happening, posted for
# one issue: the redacted title only, never anything from an occurrence.
class SlackMessage::IssueAlert < SlackMessage
  def initialize(issue, kind, now: Time.current)
    @issue, @kind, @now = issue, kind.to_s, now
    @project = issue.project
  end

  private
    attr_reader :issue, :kind, :project

    def fallback_text
      escape("#{kind_label(kind)} in #{project.name}: #{title.truncate(150)}")
    end

    def blocks
      [ section("*#{escape(kind_label(kind))}* in *#{escape(project.name)}*\n#{escape(title)}"),
        fields(details),
        button("Open #{issue.short_id}", project_issue_url(project, issue)) ]
    end

    def title = (issue.message.presence || issue.exception_class).squish.truncate(TITLE_LENGTH)

    def details
      [ [ "Environments", escape(issue.environments.join(", ").presence || "—") ],
        [ "Events", "#{count(issue.events_count, 'event')} · #{count(issue.users_count, 'user')}" ],
        *last_hour,
        [ "First seen", slack_time(issue.first_seen_at) ],
        [ "Last seen", slack_time(issue.last_seen_at) ] ]
    end

    def last_hour
      return [] unless kind == "still_happening"

      events = count(IssueHourlyCount.trailing_hour(issue, now: @now), "event")
      [ [ "Last hour", "#{events} (threshold #{project.still_happening_threshold.to_i.to_fs(:delimited)})" ] ]
    end
end
