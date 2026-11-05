# Finds a trace for the trace page, or explains why it is gone
# (docs/ARCHITECTURE.md §13.8). The project is already scoped to the
# viewer's account. A trace older than the account's retention is treated
# as gone even before the next prune (downgrades apply at query time).
#
# - found: #trace
# - expired (410 page): a valid UUIDv7 whose embedded time lies between the
#   app's creation and now; #reason is :plan (hosted, beyond the account's
#   retention but within the longest one), :retention (beyond the retention
#   otherwise) or :trimmed (within it: a slower request replaced it)
# - anything else is unknown (404)
class Apm::TraceLookup
  attr_reader :project, :entitlements, :now

  def initialize(project, id, entitlements:, now: Time.current)
    @project = project
    @uuid = Apm::TraceId.uuid(id)
    @entitlements = entitlements
    @now = now
  end

  def trace
    return @trace if defined?(@trace)

    @trace = @uuid && project.apm_traces.where(minute: cutoff..).find_by(uuid: @uuid)
  end

  def found? = trace.present?

  def expired? = !found? && issued_at.present? && issued_at.between?(project.created_at, now)

  def reason
    return :trimmed if issued_at >= cutoff
    return :plan if !entitlements.unlimited? && issued_at >= now - Entitlements::MAX_APM_RETENTION_DAYS.days

    :retention
  end

  def retention_days = entitlements.apm_retention_days

  def cutoff = now - retention_days.days

  private
    def issued_at = @uuid && Apm::TraceId.time(@uuid)
end
