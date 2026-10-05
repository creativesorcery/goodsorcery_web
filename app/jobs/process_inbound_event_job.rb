# Processes one accepted ingest request. The only argument is the GlobalID of
# the InboundEvent, so no payload bytes ever reach Redis, Sidekiq retry sets
# or job logs. Database errors are re-raised without their message, because
# Postgres details can quote row values.
class ProcessInboundEventJob < ApplicationJob
  queue_as :ingest

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5
  # The inbound event is gone: it was already processed (or discarded).
  discard_on ActiveJob::DeserializationError

  def perform(inbound_event)
    Ingest::Processor.new(inbound_event).process
  rescue ActiveRecord::Deadlocked
    raise
  rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => error
    raise Ingest::ProcessingFailed, "#{error.class.name} while processing inbound event #{inbound_event.id}", cause: nil
  end
end
