# Atomic counter upserts for one event: issue and project hourly counts, tag
# value counts and the affected-user row. Multi-row upserts are sorted so
# concurrent transactions lock rows in the same order. The project hour is a
# separate step so the processor can lock that hot row last.
class Ingest::Rollups
  USER_ON_DUPLICATE = <<~SQL.squish.freeze
    events_count = issue_users.events_count + 1,
    first_seen_at = LEAST(issue_users.first_seen_at, EXCLUDED.first_seen_at),
    last_seen_at = GREATEST(issue_users.last_seen_at, EXCLUDED.last_seen_at),
    identity_digests = ARRAY(SELECT DISTINCT unnest(issue_users.identity_digests || EXCLUDED.identity_digests) ORDER BY 1)
  SQL

  def initialize(issue_id, project, event)
    @issue_id, @project, @event = issue_id, project, event
  end

  # Per-issue rows. Returns true when this is the first event of this user for the issue.
  def increment_issue
    increment_issue_hour
    increment_tags
    increment_user
  end

  def increment_project
    ProjectHourlyCount.upsert({ project_id: @project.id, environment: @event.environment, hour:, count: 1 },
                              on_duplicate: Arel.sql("count = project_hourly_counts.count + 1"), record_timestamps: false)
  end

  private
    def hour = @hour ||= TimeSeries.align(@event.occurred_at, 1.hour)

    def increment_issue_hour
      IssueHourlyCount.upsert({ issue_id: @issue_id, hour:, count: 1 },
                              on_duplicate: Arel.sql("count = issue_hourly_counts.count + 1"), record_timestamps: false)
    end

    def increment_tags
      rows = Ingest::TagRows.new(@issue_id, @event.tags).to_a
      return if rows.empty?

      IssueTagCount.upsert_all(rows, on_duplicate: Arel.sql("count = issue_tag_counts.count + 1"), record_timestamps: false)
    end

    def increment_user
      return false unless @event.user_identity.present?

      result = IssueUser.upsert(user_row, on_duplicate: Arel.sql(USER_ON_DUPLICATE),
                                returning: Arel.sql("(xmax = 0) AS inserted"), record_timestamps: false)
      result.rows.dig(0, 0) == true
    end

    def user_row
      identity = @event.user_identity
      { issue_id: @issue_id, project_id: @project.id, user_digest: identity.primary_digest,
        identity_digests: identity.digests, events_count: 1, first_seen_at: @event.occurred_at, last_seen_at: @event.occurred_at }
    end
end
