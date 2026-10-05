# One "key:value" filter of an issue query, e.g. is:unresolved, env:production,
# level:error, assigned:me, user:mara@example.com or class:NoMethodError.
class IssueQuery::Chip < Data.define(:key, :value)
  KEYS = %w[is env level assigned user class].freeze
  PATTERN = /\A(#{KEYS.join("|")}):(\S{1,255})\z/i
  DOWNCASED_KEYS = %w[is env level assigned].freeze
  TAB_KEYS = %w[is assigned].freeze

  STATUS_SCOPES = {
    "unresolved" => :unresolved,
    "resolved" => :resolved,
    "ignored" => :ignored,
    "for_review" => :for_review,
    "new" => :newly_seen,
    "regressed" => :regressed
  }.freeze

  # "env:production" → Chip; anything else → nil (free text).
  def self.parse(token)
    match = PATTERN.match(token.to_s)
    new(key: match[1], value: match[2]) if match
  end

  def initialize(key:, value:)
    key = key.to_s.downcase
    super(key:, value: DOWNCASED_KEYS.include?(key) ? value.to_s.downcase : value.to_s)
  end

  def to_s = "#{key}:#{value}"

  # Short form for display: user digests are 64 hex characters.
  def label
    PrivateDigest.digest?(value) ? "#{key}:#{value.first(12)}…" : to_s
  end

  # Status and assignment chips are what the triage tabs rewrite.
  def tab? = TAB_KEYS.include?(key)

  def apply(relation, user: nil)
    case key
    when "is" then status_scope(relation)
    when "env" then relation.in_environment(value)
    when "level" then level_scope(relation)
    when "assigned" then assignment_scope(relation, user)
    when "user" then relation.affecting(IssueUser.identity_digests_for(value))
    when "class" then relation.where("issues.exception_class ILIKE ?", Issue.sanitize_sql_like(value))
    end
  end

  private
    def status_scope(relation)
      scope = STATUS_SCOPES[value]
      scope ? relation.public_send(scope) : relation.none
    end

    def level_scope(relation)
      Issue::LEVELS.include?(value) ? relation.at_level(value) : relation.none
    end

    def assignment_scope(relation, user)
      return relation.unassigned if value == "none"
      return relation.assigned_to(user) if value == "me" && user

      relation.none
    end
end
