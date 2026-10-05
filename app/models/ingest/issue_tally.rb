# Finds or race-safely creates the issue for an event, and applies the event to
# the issue's counters in one locking UPDATE (ARCHITECTURE.md §2.5).
#
# The issue row is locked FOR NO KEY UPDATE: that still serialises counter
# updates, but unlike FOR UPDATE it does not conflict with the FOR KEY SHARE
# locks that concurrent occurrence and rollup inserts take through their
# foreign keys, which deadlocked concurrent events of one issue.
class Ingest::IssueTally
  COUNT_SQL = <<~SQL.squish.freeze
    WITH previous AS (
      SELECT id, status FROM issues WHERE id = :issue_id FOR NO KEY UPDATE
    )
    UPDATE issues SET
      events_count  = issues.events_count + 1,
      users_count   = issues.users_count + :new_user,
      first_seen_at = LEAST(issues.first_seen_at, :occurred_at),
      last_seen_at  = GREATEST(issues.last_seen_at, :occurred_at),
      environments  = CASE WHEN CAST(:env AS varchar) = ANY(issues.environments) THEN issues.environments
                           ELSE array_append(issues.environments, CAST(:env AS varchar)) END,
      status        = CASE WHEN issues.status = 'resolved' THEN 'unresolved' ELSE issues.status END,
      regressed_at  = CASE WHEN issues.status = 'resolved' THEN :now ELSE issues.regressed_at END,
      resolved_at   = CASE WHEN issues.status = 'resolved' THEN NULL ELSE issues.resolved_at END,
      updated_at    = :now
    FROM previous WHERE issues.id = previous.id
    RETURNING issues.*, previous.status AS previous_status
  SQL

  attr_reader :issue_id

  def initialize(project, event)
    @project, @event = project, event
    @created = false
  end

  def created? = @created

  # Runs before the event transaction: finds the issue or, on a miss,
  # reserves its number in a short statement of its own, so the projects row
  # is not locked for the whole transaction.
  def prepare
    @issue_id = existing_issue_id
    @number = @project.allocate_issue_number unless @issue_id
    self
  end

  # Plain SELECT first; only a miss inserts. Losing an insert race to a
  # concurrent processor falls back to the winner's id.
  def find_or_create_issue_id
    @issue_id ||= existing_issue_id || create_issue_id || existing_issue_id
  end

  # Applies the event to the issue row and returns the updated Issue, with the
  # extra attribute `previous_status`. This is the only lock on the issue row.
  def count(new_user:)
    sql = Issue.sanitize_sql([ COUNT_SQL, { issue_id:, new_user: new_user ? 1 : 0,
                                            occurred_at: @event.occurred_at, env: @event.environment, now: Time.current } ])
    Issue.uncached { Issue.find_by_sql(sql).first }.tap { |issue| issue.association(:project).target = @project }
  end

  private
    def existing_issue_id
      Issue.uncached { Issue.where(project_id: @project.id, fingerprint: @event.fingerprint).pick(:id) }
    end

    def create_issue_id
      result = Issue.insert(new_issue_attributes, unique_by: %i[project_id fingerprint], returning: %i[id])
      @created = result.rows.any?
      result.rows.first&.first
    end

    # Numbers lost to a failed insert leave gaps, which is accepted.
    def number = @number ||= @project.allocate_issue_number

    def new_issue_attributes
      { project_id: @project.id, number:, fingerprint: @event.fingerprint,
        exception_class: @event.exception_class, message: @event.redacted_message, culprit: @event.culprit,
        transaction_name: @event.transaction_name, level: @event.level, status: "unresolved",
        environments: [ @event.environment ], first_seen_at: @event.occurred_at, last_seen_at: @event.occurred_at,
        events_count: 0, users_count: 0 }
    end
end
