class IssueActivity < ApplicationRecord
  KINDS = %w[regressed reached_production resolved reopened ignored assigned unassigned note].freeze

  belongs_to :issue, inverse_of: :activities
  belongs_to :user, optional: true
  belongs_to :subject_user, class_name: "User", optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true

  encrypts :body

  validates :body, presence: true, length: { maximum: 2_000 }, if: :note?
  validates :body, absence: true, unless: :note?

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # One INSERT for a batch of triaged issues.
  def self.record_all(issue_ids, kind:, user: nil, subject_user: nil)
    now = Time.current
    rows = issue_ids.map do |issue_id|
      { issue_id:, kind: kind.to_s, user_id: user&.id, subject_user_id: subject_user&.id, created_at: now }
    end
    insert_all(rows) if rows.any?
  end
end
