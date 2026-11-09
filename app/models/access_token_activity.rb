# One change made through the MCP endpoint (docs/ARCHITECTURE.md §14.5): the
# token, its member, the action and the issue ids. Shown on the MCP server
# page (the last RECENT_PER_TOKEN per token). Never holds note text or
# captured data.
class AccessTokenActivity < ApplicationRecord
  ACTIONS = %w[resolve ignore unresolve note].freeze
  RECENT_PER_TOKEN = 20
  KEPT_FOR = 90.days
  LABELS = { "resolve" => "Resolved", "ignore" => "Ignored", "unresolve" => "Reopened", "note" => "Added a note to" }.freeze

  belongs_to :personal_access_token, inverse_of: :activities
  belongs_to :user

  validates :action, inclusion: { in: ACTIONS }

  # The last RECENT_PER_TOKEN rows of each token, newest first, in one query:
  # { token_id => [activity, …] }.
  def self.recent_by_token(token_ids)
    ranked = where(personal_access_token_id: token_ids)
      .select("access_token_activities.*", "ROW_NUMBER() OVER (PARTITION BY personal_access_token_id " \
              "ORDER BY created_at DESC, id DESC) AS position")
    from(ranked, :access_token_activities).where("position <= ?", RECENT_PER_TOKEN)
      .order(created_at: :desc, id: :desc).to_a.group_by(&:personal_access_token_id)
  end

  def self.record(token, action, issue_ids)
    create!(personal_access_token: token, user_id: token.user_id, action:, issue_ids:)
  end

  def label = LABELS.fetch(action)
end
