# The decrypted parts of one occurrence that tool results share: when and
# where it happened, the message, the app-first backtrace and the
# breadcrumbs. Without the request_data scope the message is redacted like
# issue titles (Ingest::MessageRedactor) and frame locals are left out.
#
# All captured text of the occurrence spends one budget (#budget, BYTES),
# which get_occurrence shares with its other sections, so the result stays
# small even for an event at the ingest size limit.
# Captured data: never log or cache anything built here.
class Mcp::OccurrenceDetails
  FULL_MESSAGE = 2_000
  BYTES = 16_000
  BACKTRACE_BYTES = 6_000
  BREADCRUMB_BYTES = 4_000

  attr_reader :occurrence, :budget

  def initialize(occurrence, request_data:)
    @occurrence = occurrence
    @request_data = request_data
    @budget = Mcp::OutputBudget.new(BYTES)
  end

  def to_h
    { id: occurrence.uuid, occurred_at: Mcp::Text.time(occurrence.occurred_at), environment: occurrence.environment,
      release: occurrence.release, message:, backtrace: backtrace.frames, backtrace_frames_total: backtrace.total,
      breadcrumbs: breadcrumbs.crumbs, breadcrumbs_total: breadcrumbs.total }
  end

  def text_lines
    [ "Occurrence #{occurrence.uuid} at #{Mcp::Text.time(occurrence.occurred_at)} · #{occurrence.environment}" \
      "#{" · release #{occurrence.release}" if occurrence.release}",
      "Message: #{message}", "", "Backtrace (app frames first):", *backtrace.text_lines,
      "", "Breadcrumbs (ms before the error):", *(breadcrumbs.text_lines.presence || [ "  none" ]) ]
  end

  def message
    @message ||= budget.string(@request_data ? occurrence.exception_message : redacted_message, FULL_MESSAGE).presence || "(no message)"
  end

  def backtrace
    @backtrace ||= Mcp::BacktraceSummary.new(occurrence.frames, locals: @request_data, budget: budget.section(BACKTRACE_BYTES))
  end

  def breadcrumbs = @breadcrumbs ||= Mcp::BreadcrumbSummary.new(occurrence.breadcrumbs, budget: budget.section(BREADCRUMB_BYTES))

  private
    def redacted_message = Ingest::MessageRedactor.new.redact(occurrence.exception_message)
end
