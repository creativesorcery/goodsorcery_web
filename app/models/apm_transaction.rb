# What ran (docs/ARCHITECTURE.md §13.2): a web endpoint (Controller#action,
# with its verb and route pattern) or a job class (with adapter and queue),
# per app, environment and kind. Names, routes and labels are code
# identifiers, plaintext like issues.transaction_name. Each environment and
# kind also has one total row ("All web requests" / "All background jobs")
# that holds the app-wide histogram; it is never listed and never counts
# toward the cap of Apm::MAX_TRANSACTIONS names, past which data is counted
# under OTHER_NAME. Rows are created by Apm::TransactionRegistry.
class ApmTransaction < ApplicationRecord
  KINDS = %w[web job].freeze
  MAX_TRANSACTIONS = Apm::MAX_TRANSACTIONS
  OTHER_NAME = "(other)".freeze
  TOTAL_NAMES = { "web" => "All web requests", "job" => "All background jobs" }.freeze

  belongs_to :project, inverse_of: :apm_transactions
  has_many :apm_minute_stats, inverse_of: :apm_transaction
  has_many :apm_hourly_stats, inverse_of: :apm_transaction
  has_many :apm_traces, inverse_of: :apm_transaction

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, length: { maximum: 255 }

  scope :listed, -> { where(total: false) }
  scope :totals, -> { where(total: true) }
  scope :web, -> { where(kind: "web") }
  scope :jobs, -> { where(kind: "job") }
  scope :of_kind, ->(kind) { where(kind:) }
  scope :for_environment, ->(environment) { where(environment:) }
  # Case-insensitive substring of the name or route (q is capped at 100 chars).
  scope :matching, ->(q) do
    q = q.to_s.strip.first(100)
    q.empty? ? all : where("apm_transactions.name ILIKE :q OR apm_transactions.route ILIKE :q", q: "%#{sanitize_sql_like(q)}%")
  end

  # Environments of an app that have performance data, most recently seen first.
  def self.environments_of(project)
    where(project:).group(:environment).order(Arel.sql("MAX(last_seen_at) DESC")).pluck(:environment)
  end

  # The total row of an environment and kind, or nil before any data.
  def self.total_for(project, environment, kind)
    totals.find_by(project:, environment:, kind:)
  end

  def web? = kind == "web"

  def job? = kind == "job"

  def other? = name == OTHER_NAME

  # "POST /checkout"; nil without a route (jobs, (other), totals).
  def route_label
    [ http_method, route ].compact_blank.join(" ").presence if route.present?
  end
end
