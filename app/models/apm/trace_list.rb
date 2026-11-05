# One page of a transaction's slow traces for the endpoint page
# (docs/ARCHITECTURE.md §13.9): within the range (already clamped to the
# retention), sorted "slowest" or "newest", ApmTrace::PER_PAGE per page,
# with the issues their error events belong to resolved in one query (their
# project set from the transaction's, so short ids and links need no more).
#
#   list = Apm::TraceList.new(transaction, range, sort: "slowest", page: 1)
#   list.traces        # => [ApmTrace, …]
#   list.total         # => 131
#   list.issue_for(trace)  # => Issue or nil
class Apm::TraceList
  PER_PAGE = ApmTrace::PER_PAGE

  attr_reader :transaction, :range, :sort, :page

  def initialize(transaction, range, sort:, page:)
    @transaction = transaction
    @range = range
    @sort = sort
    @page = page
  end

  def traces = @traces ||= scope.page_of(page).to_a

  def total = @total ||= scope.unscope(:order).count

  def empty? = total.zero?

  def first_number = ((page - 1) * PER_PAGE) + 1

  def last_number = first_number + traces.size - 1

  def previous_page? = page > 1

  def next_page? = page * PER_PAGE < total

  # The issue of the trace's reported error event, when that event is still stored.
  def issue_for(trace) = trace.error_event_uuid && issues_by_event[trace.error_event_uuid]

  private
    def scope = ApmTrace.listing(transaction, range, sort:)

    def issues_by_event
      @issues_by_event ||= begin
        uuids = traces.filter_map(&:error_event_uuid).uniq
        uuids.empty? ? {} : issues_of(transaction.project.occurrences.where(uuid: uuids).includes(:issue).to_a)
      end
    end

    def issues_of(occurrences)
      issues = occurrences.map(&:issue)
      ActiveRecord::Associations::Preloader.new(records: issues, associations: :project, available_records: [ transaction.project ]).call
      occurrences.to_h { [ it.uuid, it.issue ] }
    end
end
