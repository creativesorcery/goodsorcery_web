# "Across all projects, last hour" on the overview: unresolved issues seen in
# the last hour plus issues resolved in the last hour, newest first. Two
# queries, with projects (and resolvers) preloaded.
class RecentFeed
  WINDOW = 1.hour
  ISSUE_LIMIT = 8
  RESOLUTION_LIMIT = 4

  # kind: :new, :regressed, :seen or :resolved. `user` is the resolver.
  Entry = Data.define(:kind, :issue, :at, :user) do
    def resolved? = kind == :resolved
  end

  def initialize(account, now: Time.current)
    @account = account
    @since = now - WINDOW
  end

  def entries
    @entries ||= (issue_entries + resolution_entries).sort_by { |entry| -entry.at.to_f }
  end

  def empty? = entries.empty?

  private
    def project_ids
      @account.projects.select(:id)
    end

    def issue_entries
      seen_issues.map { |issue| Entry.new(kind: kind_of(issue), issue:, at: issue.last_seen_at, user: nil) }
    end

    def resolution_entries
      resolutions.map { |activity| Entry.new(kind: :resolved, issue: activity.issue, at: activity.created_at, user: activity.user) }
    end

    def seen_issues
      Issue.unresolved.where(project_id: project_ids, last_seen_at: @since..)
        .includes(:project).order(last_seen_at: :desc, id: :desc).limit(ISSUE_LIMIT)
    end

    def resolutions
      IssueActivity.resolved.where(created_at: @since..).joins(:issue).where(issues: { project_id: project_ids })
        .includes(:user, issue: :project).order(created_at: :desc, id: :desc).limit(RESOLUTION_LIMIT)
    end

    def kind_of(issue)
      return :new if issue.new?

      issue.regressed? ? :regressed : :seen
    end
end
