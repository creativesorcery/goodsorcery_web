# A group of occurrences sharing a fingerprint. The summary columns
# (exception_class, redacted message, culprit, transaction_name) are plaintext
# by design for search; everything else captured lives in encrypted payloads.
class Issue < ApplicationRecord
  include Issue::Searchable, Issue::Triage, Issue::Broadcasting

  STATUSES = %w[unresolved resolved ignored].freeze
  LEVELS = %w[fatal error warning info].freeze
  SHORT_ID = /\A[A-Z]{1,6}-\d+\z/i

  belongs_to :project, inverse_of: :issues
  belongs_to :assignee, class_name: "User", optional: true

  has_many :occurrences, inverse_of: :issue
  has_many :hourly_counts, class_name: "IssueHourlyCount", inverse_of: :issue
  has_many :tag_counts, class_name: "IssueTagCount", inverse_of: :issue
  has_many :issue_users, inverse_of: :issue
  has_many :activities, class_name: "IssueActivity", inverse_of: :issue

  enum :status, STATUSES.index_by(&:itself), validate: true
  enum :level, LEVELS.index_by(&:itself), validate: true, scopes: false

  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :fingerprint, length: { is: 64 }
  validates :exception_class, presence: true, length: { maximum: 255 }
  validates :message, length: { maximum: 1_024 }
  validates :first_seen_at, :last_seen_at, presence: true
  validate :assignee_is_member, if: -> { assignee_id_changed? && assignee }

  def self.find_by_short_id!(param)
    find_by!(number: param.to_s[/\d+\z/])
  end

  def short_id = "#{project.issue_prefix}-#{number}"

  def to_param = short_id

  def new? = unresolved? && first_seen_at >= 24.hours.ago

  def regressed? = unresolved? && regressed_at.present?

  def accessible_by?(user) = project.accessible_by?(user)

  def fingerprint_label = fingerprint.to_s.first(12)

  private
    def assignee_is_member
      errors.add(:assignee, "must be a member of this account") unless project.account.accessible_by?(assignee)
    end
end
