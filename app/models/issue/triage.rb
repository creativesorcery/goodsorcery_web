# Status and assignment changes, each recorded as an IssueActivity and
# followed by a live-update broadcast.
module Issue::Triage
  extend ActiveSupport::Concern

  BULK_LIMIT = 100

  def resolve(by:)
    return self if resolved?

    triage :resolved, by:, status: :resolved, resolved_at: Time.current, regressed_at: nil
  end

  def ignore(by:)
    return self if ignored?

    triage :ignored, by:, status: :ignored
  end

  def reopen(by:)
    return self if unresolved?

    triage :reopened, by:, status: :unresolved, resolved_at: nil
  end

  def assign(user, by:)
    return self if assignee_id == user.id

    triage :assigned, by:, subject_user: user, assignee: user
  end

  def unassign(by:)
    return self if assignee_id.nil?

    triage :unassigned, by:, subject_user: assignee, assignee: nil
  end

  class_methods do
    # via: "mcp" marks changes made through the MCP endpoint (IssueActivity::VIAS).
    def resolve_all(by:, via: nil)
      triage_all :resolved, by:, via:, status: "resolved", resolved_at: Time.current, regressed_at: nil
    end

    def ignore_all(by:, via: nil)
      triage_all :ignored, by:, via:, status: "ignored"
    end

    def reopen_all(by:, via: nil)
      triage_all :reopened, by:, via:, status: "unresolved", resolved_at: nil
    end

    def assign_all(user, by:)
      raise ArgumentError, "assignee must be an account member" unless assignable?(user)

      triage_all :assigned, by:, subject_user: user, assignee_id: user.id
    end

    private
      # Changes up to BULK_LIMIT issues of the current relation that are not
      # already in the target state; returns the ids that changed.
      def triage_all(kind, by:, subject_user: nil, via: nil, **changes)
        ids = pending_ids(changes)
        return ids if ids.empty?

        transaction do
          where(id: ids).update_all(changes.merge(updated_at: Time.current))
          IssueActivity.record_all(ids, kind:, user: by, subject_user:, via:)
        end
        broadcast_triage(ids)
        ids
      end

      def pending_ids(changes)
        changes.except(:resolved_at, :regressed_at).inject(all) do |relation, (column, value)|
          relation.where("issues.#{column} IS DISTINCT FROM ?", value)
        end.limit(BULK_LIMIT).pluck(:id)
      end

      def assignable?(user)
        account_ids = Project.where(id: select(:project_id)).select(:account_id)
        user.present? && user.memberships.where(account_id: account_ids).exists?
      end

      def broadcast_triage(ids)
        issues = unscoped { where(id: ids).includes(:project).to_a }
        issues.each(&:broadcast_changes_later)
        issues.map(&:project).uniq.each do |project|
          project.expire_unresolved_counts
          project.broadcast_changes_later
        end
      end
  end

  private
    def triage(kind, by:, subject_user: nil, **changes)
      transaction do
        update!(changes)
        activities.create!(kind:, user: by, subject_user:)
      end
      broadcast_changes_later
      project.expire_unresolved_counts
      project.broadcast_changes_later
      self
    end
end
