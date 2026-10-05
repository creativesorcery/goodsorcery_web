class Project < ApplicationRecord
  include Project::Broadcasting

  COLORS = %w[iris coral lilac mint].freeze
  DEFAULT_ENVIRONMENTS = %w[production staging].freeze

  belongs_to :account, inverse_of: :projects
  has_many :api_keys, -> { order(:id) }, inverse_of: :project
  has_many :issues, inverse_of: :project
  has_many :occurrences, inverse_of: :project
  has_many :inbound_events, inverse_of: :project
  has_many :project_hourly_counts, inverse_of: :project

  enum :platform, { rails: "rails", rails_api: "rails_api", sidekiq: "sidekiq", ruby: "ruby" }, validate: true
  enum :color, COLORS.index_by(&:itself), validate: true, prefix: true

  attr_readonly :slug

  normalizes :name, with: ->(name) { name.squish }
  normalizes :issue_prefix, with: ->(prefix) { prefix.strip.upcase }
  normalizes :scrub_fields, with: ->(fields) { Array(fields).map { |f| f.to_s.strip.downcase }.compact_blank.uniq.first(50) }

  validates :name, presence: true, length: { maximum: 60 }
  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validates :issue_prefix, format: { with: /\A[A-Z]{1,6}\z/ }
  validates :retention_days, numericality: { only_integer: true, in: 1..365 }

  before_validation :assign_defaults, on: :create
  after_create :create_default_api_keys

  def to_param = slug

  def accessible_by?(user) = account.accessible_by?(user)

  def listening? = first_event_at.nil?

  # API key environments in creation order; uses the loaded association when present.
  def environments
    api_keys.loaded? ? api_keys.map(&:environment) : api_keys.pluck(:environment)
  end

  def default_api_key
    api_keys.min_by(&:id)
  end

  def unresolved_count
    issues.unresolved.count
  end

  # Atomically reserves the next per-project issue number (row lock until commit).
  def allocate_issue_number
    sql = "UPDATE projects SET issues_sequence = issues_sequence + 1 WHERE id = ? RETURNING issues_sequence"
    # uncached: an UPDATE ... RETURNING must never be answered from the query cache.
    self.class.uncached { self.class.connection.select_value(self.class.sanitize_sql([ sql, id ])) }
  end

  def record_first_event(runtime_label:, at:)
    self.class.where(id:).update_all([
      "first_event_at = COALESCE(first_event_at, ?), runtime_label = COALESCE(?, runtime_label)", at, runtime_label
    ])
  end

  private
    def assign_defaults
      self.slug ||= Project::Slug.new(account, name).unique if account && name.present?
      self.issue_prefix ||= Project::Slug.prefix_for(slug)
      self.color = COLORS[account.projects.count % COLORS.size] if account && !color_changed?
    end

    def create_default_api_keys
      DEFAULT_ENVIRONMENTS.each { |environment| api_keys.create!(environment:, created_by: Current.user) }
    end
end
