# Processes one accepted performance batch. The only argument is the integer
# id of the ApmInboundBatch, so no payload bytes ever reach Redis, Sidekiq
# retry sets or job logs. Database errors are re-raised by class name only,
# because Postgres messages can quote row values.
class ProcessApmBatchJob < ApplicationJob
  queue_as :apm

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

  def perform(apm_inbound_batch_id)
    Apm::BatchProcessor.new(apm_inbound_batch_id).process
  rescue ActiveRecord::Deadlocked
    raise
  rescue ActiveRecord::StatementInvalid, JSON::ParserError, KeyError => error
    Rails.logger.error("APM batch #{apm_inbound_batch_id} failed: #{error.class.name}")
    raise Apm::ProcessingFailed, "#{error.class.name} while processing APM batch #{apm_inbound_batch_id}", cause: nil
  end
end
