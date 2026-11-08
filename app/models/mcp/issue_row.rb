# One issue as list tools show it: the redacted title and the other
# plaintext summary columns (docs/ARCHITECTURE.md §1.5), counts, times and a
# link. Nothing here decrypts captured data.
class Mcp::IssueRow
  def initialize(issue, context)
    @issue = issue
    @context = context
  end

  def to_h
    { short_id: @issue.short_id, id: @issue.id, app: @issue.project.slug, title:,
      exception_class: @issue.exception_class, culprit: @issue.culprit, transaction: @issue.transaction_name,
      status: @issue.status, level: @issue.level, environments: @issue.environments,
      events: @issue.events_count, users: @issue.users_count,
      first_seen_at: Mcp::Text.time(@issue.first_seen_at), last_seen_at: Mcp::Text.time(@issue.last_seen_at),
      url: @context.issue_url(@issue) }
  end

  # "GS-42 [unresolved] NoMethodError: undefined method …" and a second line
  # with where it happens, environments, counts and when it was last seen.
  def text_line
    "#{@issue.short_id} [#{@issue.status}] #{@issue.exception_class}: #{title}\n    #{details}"
  end

  def title = @issue.message.presence || @issue.exception_class

  private
    def details
      origin = [ @issue.transaction_name, @issue.culprit ].compact_blank.join(" · ").presence || "unknown origin"
      environments = @issue.environments.join(", ").presence || "no environment"
      counts = "#{Mcp::Text.count(@issue.events_count)} events, #{Mcp::Text.count(@issue.users_count)} users"
      "#{origin} · #{environments} · #{counts} · last seen #{Mcp::Text.time(@issue.last_seen_at)}"
    end
end
