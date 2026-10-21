class Project < ApplicationRecord
  include Project::Broadcasting, Project::Alerting

  COLORS = %w[iris coral lilac mint].freeze
  DEFAULT_ENVIRONMENTS = %w[production staging].freeze
  PRODUCTION = "production".freeze
  MAX_PER_ACCOUNT = 100
  # Occurrences are deleted after retention_days; no app keeps them longer.
  MAX_RETENTION_DAYS = 30
  UNRESOLVED_COUNT_TTL = 10.seconds

  belongs_to :account, inverse_of: :projects
  has_many :api_keys, -> { order(:id) }, inverse_of: :project
  has_many :issues, inverse_of: :project
  has_many :occurrences, inverse_of: :project
  has_many :inbound_events, inverse_of: :project
  has_many :project_hourly_counts, inverse_of: :project

  enum :platform, { rails: "rails", ruby: "ruby" }, validate: true
  enum :color, COLORS.index_by(&:itself), validate: true, prefix: true

  attr_readonly :slug

  normalizes :name, with: ->(name) { name.squish }
  normalizes :issue_prefix, with: ->(prefix) { prefix.strip.upcase }
  normalizes :scrub_fields, with: ->(fields) { Array(fields).map { |f| f.to_s.strip.downcase }.compact_blank.uniq.first(50) }
  normalizes :default_environment, with: ->(environment) { environment.strip.downcase.presence }

  validates :name, presence: true, length: { maximum: 60 }
  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validates :issue_prefix, format: { with: /\A[A-Z]{1,6}\z/ }, uniqueness: { scope: :account_id }
  validates :retention_days, numericality: { only_integer: true, in: 1..MAX_RETENTION_DAYS }
  validates :default_environment, inclusion: { in: :environments, message: "must be one of this app's environments" }, allow_nil: true
  validate :account_has_room, on: :create

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

  def unresolved_count(environment = nil)
    (environment ? issues.in_environment(environment) : issues).unresolved.count
  end

  # For the sidebar badge and the issue list heading, which live reloads
  # re-render every few seconds during ingest. Only the number is cached;
  # triage expires it at once (#expire_unresolved_counts).
  def cached_unresolved_count(environment = nil)
    Rails.cache.fetch(unresolved_count_key(environment), expires_in: UNRESOLVED_COUNT_TTL) { unresolved_count(environment) }
  end

  def expire_unresolved_counts
    Rails.cache.delete_multi([ nil, *environments ].map { |environment| unresolved_count_key(environment) })
  end

  # Atomically reserves the next per-project issue number. The row stays
  # locked until commit, so ingest calls it outside the event transaction.
  def allocate_issue_number
    sql = "UPDATE projects SET issues_sequence = issues_sequence + 1 WHERE id = ? RETURNING issues_sequence"
    # uncached: an UPDATE ... RETURNING must never be answered from the query cache.
    self.class.uncached { self.class.connection.select_value(self.class.sanitize_sql([ sql, id ])) }
  end

  # Writes (and locks) the project row only when something changes.
  def record_first_event(runtime_label:, at:)
    changes_needed = "first_event_at IS NULL OR runtime_label IS DISTINCT FROM COALESCE(?, runtime_label)"
    self.class.where(id:).where(changes_needed, runtime_label).update_all([
      "first_event_at = COALESCE(first_event_at, ?), runtime_label = COALESCE(?, runtime_label)", at, runtime_label
    ])
  end

  private
    def unresolved_count_key(environment) = [ "unresolved_count", id, environment ]

    def account_has_room
      return unless account && account.projects.count >= MAX_PER_ACCOUNT

      errors.add(:base, "An account can have at most #{MAX_PER_ACCOUNT} apps")
    end

    def assign_defaults
      self.slug ||= Project::Slug.new(account, name).unique if account && name.present?
      self.issue_prefix ||= account ? Project::Slug.unique_prefix_for(account, slug) : Project::Slug.prefix_for(slug)
      self.color = COLORS[account.projects.count % COLORS.size] if account && !color_changed?
    end

    def create_default_api_keys
      DEFAULT_ENVIRONMENTS.each { |environment| api_keys.create!(environment:, created_by: Current.user) }
      start_on_production
    end

    # A new app's issue list opens on production when it has a production
    # key once created. Only at creation: later, nil is someone's choice of
    # "All environments" and is kept.
    def start_on_production
      update_column(:default_environment, PRODUCTION) if default_environment.nil? && api_keys.exists?(environment: PRODUCTION)
    end
end
