# The stored, normalised occurrence payload (ARCHITECTURE.md §3.3). It is only
# ever written to the encrypted Occurrence#payload column.
class Ingest::Payload
  def initialize(event)
    @event = event
  end

  def to_h
    { exception:, transaction: @event.transaction, request: @event.request.summary,
      params: @event.request.params, headers: @event.request.headers, session: @event.request.session,
      job: @event.job, user: @event.user, breadcrumbs: @event.breadcrumbs.map(&:to_h), context: @event.context,
      tags: @event.tags, notifier: @event.notifier }
  end

  def to_json(*) = to_h.to_json

  private
    def exception
      { class: @event.exception_class, message: @event.message, backtrace: @event.frames.map(&:to_h) }
    end
end
