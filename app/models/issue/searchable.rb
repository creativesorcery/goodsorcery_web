module Issue::Searchable
  extend ActiveSupport::Concern

  MAX_TERMS = 10
  SORTS = {
    "last_seen" => :last_seen_at,
    "first_seen" => :first_seen_at,
    "events" => :events_count,
    "users" => :users_count
  }.freeze

  included do
    scope :newly_seen, -> { unresolved.where(first_seen_at: 24.hours.ago..) }
    scope :regressed, -> { unresolved.where.not(regressed_at: nil) }
    scope :for_review, -> {
      unresolved.where("issues.first_seen_at >= :t OR issues.regressed_at IS NOT NULL", t: 24.hours.ago)
    }

    # Containment (@>) so the GIN index on environments is used.
    scope :in_environment, ->(env) { where("issues.environments @> ARRAY[?]::varchar[]", env.to_s) }
    scope :at_level, ->(level) { where(level: level.to_s) }
    scope :assigned_to, ->(user) { where(assignee_id: user&.id) }
    scope :unassigned, -> { where(assignee_id: nil) }

    scope :matching, ->(text) {
      text.to_s.downcase.split.first(MAX_TERMS).inject(all) do |relation, term|
        relation.where("issues.search_text LIKE ?", "%#{sanitize_sql_like(term)}%")
      end
    }

    scope :affecting, ->(digests) {
      where(id: IssueUser.where("identity_digests && ARRAY[?]::varchar[]", Array(digests)).select(:issue_id))
    }

    scope :sorted_by, ->(key) { order(SORTS.fetch(key.to_s, :last_seen_at) => :desc, id: :desc) }
  end
end
