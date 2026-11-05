# The timeline of one slow request or job run (docs/ARCHITECTURE.md §13.2):
# at most one per transaction per minute while its hour is open (a slower
# one replaces it, Apm::TraceUpsert) and the KEPT_PER_CLOSED_HOUR slowest per
# transaction for each closed hour (Apm::TraceTrim). The layer totals,
# counts, status and ids are plaintext numbers; everything captured (SQL,
# paths, hosts, call sites, code) is in the encrypted payload, read through
# #details. Look traces up through a project, never unscoped.
class ApmTrace < ApplicationRecord
  KEPT_PER_CLOSED_HOUR = 3
  SORTS = %w[slowest newest].freeze
  PER_PAGE = 20

  belongs_to :project, inverse_of: :apm_traces
  belongs_to :apm_transaction, inverse_of: :apm_traces

  encrypts :payload

  scope :since, ->(time) { where(minute: time..) }
  scope :slowest_first, -> { order(duration_ms: :desc, id: :desc) }
  scope :newest_first, -> { order(started_at: :desc, id: :desc) }
  # "slowest" (the default) or "newest".
  scope :sorted, ->(sort) { sort.to_s == "newest" ? newest_first : slowest_first }
  scope :with_n_plus_one, -> { where(n_plus_one_count: 1..) }
  # Page n (1-based) of PER_PAGE; out-of-range numbers read as 1.
  scope :page_of, ->(number) { offset(([ number.to_i, 1 ].max - 1) * PER_PAGE).limit(PER_PAGE) }

  # A transaction's traces within a range (its start is already clamped to
  # the retention), sorted "slowest" (default) or "newest". Chain page_of(n)
  # for a page and count for the total.
  def self.listing(transaction, range, sort: "slowest")
    where(apm_transaction_id: transaction.id).since(range.start).sorted(sort)
  end

  # The transactions among ids with an N+1 trace since a time, as a Set (one query).
  def self.transaction_ids_with_n_plus_one(ids, since:)
    with_n_plus_one.where(apm_transaction_id: ids).since(since).distinct.pluck(:apm_transaction_id).to_set
  end

  def to_param = uuid

  # The last 8 hex digits: UUIDv7's first digits are a timestamp and repeat within a minute.
  def short_id = uuid.delete("-").last(8)

  def details = @details ||= Apm::TraceDetails.new(payload)

  def open_hour?(now: Time.current) = hour >= TimeSeries.align(now, 1.hour)

  # The adjacent traces of the same transaction by start time (one query
  # each), never before `since` (the retention cutoff).
  def older(since:)
    siblings(since).where(started_at: ...started_at).order(started_at: :desc, id: :desc).first
  end

  def newer(since:)
    siblings(since).where("apm_traces.started_at > ?", started_at).order(started_at: :asc, id: :asc).first
  end

  # The stored error event this request reported, with its issue, or nil.
  def error_occurrence
    project.occurrences.includes(:issue).find_by(uuid: error_event_uuid) if error_event_uuid
  end

  private
    def siblings(since) = self.class.where(apm_transaction_id:).since(since).where.not(id:)
end
