# The trace page of one slow request or job run (docs/ARCHITECTURE.md
# §13.8–13.9): its title, layer summary, timeline axis and rows, the
# largest N+1 group, the linked error and the adjacent traces of the same
# transaction. Everything from the payload is captured data, rendered
# through ERB escaping only.
#
#   page = Apm::TracePage.new(trace, cutoff: range.retention_cutoff)
#   page.layers       # => [[:db, 1220.4, 0.415], [:http, …], [:view, …], [:ruby, …]]
#   page.axis_ticks   # => [[0, 0.0], [500, 0.17], …, [2940.2, 1.0]]
class Apm::TracePage
  LAYERS = %i[db http view ruby].freeze
  TICK_STEPS = [ 1, 2, 2.5, 5, 10 ].freeze
  TARGET_TICKS = 6

  attr_reader :trace, :cutoff, :now

  delegate :details, :duration_ms, to: :trace
  delegate :spans, :spans_dropped, to: :details

  def initialize(trace, cutoff:, now: Time.current)
    @trace = trace
    @cutoff = cutoff
    @now = now
  end

  def transaction = trace.apm_transaction

  def web? = transaction.web?

  def open_hour? = trace.open_hour?(now:)

  # "POST /checkout" for a request, the job class for a run.
  def title
    request = details.request
    return transaction.name unless web? && request.is_a?(Hash) && request["path"].present?

    [ request["method"], request["path"] ].compact_blank.join(" ")
  end

  # The first 8 characters of the request id, or nil.
  def request_id = details.request.is_a?(Hash) ? details.request["request_id"].to_s.first(8).presence : nil

  # [[layer, ms, share of the duration]] in legend order.
  def layers
    LAYERS.map do |layer|
      ms = trace.public_send(:"#{layer}_ms").to_f
      [ layer, ms, duration_ms.positive? ? ms / duration_ms : 0.0 ]
    end
  end

  # [[ms, fraction]]: round steps from 0, then the total at the end.
  def axis_ticks
    return [ [ 0, 0.0 ] ] unless duration_ms.positive?

    step = tick_step
    ticks = (0...duration_ms).step(step).take_while { it < duration_ms * 0.9 }
    (ticks.map { [ it, it / duration_ms ] } << [ duration_ms, 1.0 ])
  end

  # The N+1 group with the largest total, or nil.
  def n_plus_one = details.n_plus_one_spans.first

  # The issue of the error event this request reported, when it is still stored.
  def error_issue
    return @error_issue if defined?(@error_issue)

    @error_issue = trace.error_occurrence&.issue
  end

  def error_reported? = trace.error_event_uuid.present?

  def older = defined?(@older) ? @older : (@older = trace.older(since: cutoff))

  def newer = defined?(@newer) ? @newer : (@newer = trace.newer(since: cutoff))

  private
    # The smallest round step giving at most TARGET_TICKS intervals.
    def tick_step
      raw = duration_ms / TARGET_TICKS
      scale = 10**Math.log10(raw).floor
      TICK_STEPS.map { it * scale }.find { it >= raw }
    end
end
