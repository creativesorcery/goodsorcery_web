# Processes one stored performance batch (docs/ARCHITECTURE.md §13.4) in
# one transaction, uncached (jobs run with the query cache on, and the
# registry reads rows it may have just inserted): lock the batch row, skip
# it when it is gone or already processed, map names to transactions, add
# the metrics or store the traces, then mark it processed and drop its body.
# Logs carry the batch id, kind and counts only.
class Apm::BatchProcessor
  def initialize(batch_id, now: Time.current)
    @batch_id = batch_id
    @now = now
  end

  # Returns the number of transactions (metrics) or traces processed, or nil
  # when there was nothing to do.
  def process
    ApmInboundBatch.uncached do
      ApmInboundBatch.transaction { process_locked }
    end
  end

  private
    def process_locked
      batch = ApmInboundBatch.lock("FOR NO KEY UPDATE").find_by(id: @batch_id)
      return if batch.nil? || batch.processed?

      count = batch.metrics? ? process_metrics(batch) : process_traces(batch)
      batch.update_columns(processed_at: @now, body: nil)
      Rails.logger.info { "APM batch #{batch.id} processed: #{count} #{batch.metrics? ? "transactions" : "traces"}" }
      count
    end

    def registry(batch) = Apm::TransactionRegistry.new(project_id: batch.project_id, environment: batch.environment, now: @now)

    def process_metrics(batch)
      entries = Apm::MetricsPayload.new(batch.body).entries(now: @now)
      return 0 if entries.empty?

      registry = registry(batch)
      ids = registry.ids_for(entries, totals: true)
      total_ids = entries.map(&:kind).uniq.index_with { registry.total_id(it) }
      Apm::StatsUpsert.new(ids:, total_ids:).upsert(entries)
      entries.size
    end

    def process_traces(batch)
      traces = Apm::TracesPayload.new(batch.body).traces(now: @now)
      return 0 if traces.empty?

      ids = registry(batch).ids_for(traces)
      Apm::TraceUpsert.new(project_id: batch.project_id, ids:, now: @now).upsert(traces)
    end
end
