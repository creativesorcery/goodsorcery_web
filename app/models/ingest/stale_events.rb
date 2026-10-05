# Inbound events accepted but not processed within InboundEvent.stale's window,
# for example after a Redis outage lost their jobs.
class Ingest::StaleEvents
  # Enqueues a processing job (GlobalID only) per stale event; returns the count.
  def requeue
    InboundEvent.stale.select(:id).find_each.count do |inbound_event|
      ProcessInboundEventJob.perform_later(inbound_event)
    end
  end
end
