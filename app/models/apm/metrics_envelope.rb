# Request-time validation of a metrics payload (docs/INGEST_API.md ›
# Metrics payload). The batch is judged as a whole: any structural error
# rejects it (422) and nothing is stored. Error messages never echo payload
# content.
class Apm::MetricsEnvelope
  include Apm::JsonShape

  def initialize(body)
    @data = Ingest::Envelope.parse(body)
  end

  def valid? = errors.empty?

  def errors
    @errors ||= Apm::ShapeErrors.new.tap { check_body(it) }.to_a
  end

  # The client's batch_id when it is a UUID, otherwise a fresh UUIDv7.
  def batch_uuid
    @batch_uuid ||= Apm::TraceId.uuid(@data.is_a?(Hash) ? @data["batch_id"] : nil) || SecureRandom.uuid_v7
  end

  private
    def check_body(errors)
      return errors.add("body must be a JSON object") unless @data.is_a?(Hash)

      errors.add("histogram must be \"#{Apm::Histogram::SCHEME}\"") unless @data["histogram"] == Apm::Histogram::SCHEME
      minutes = @data["minutes"]
      sizes = Apm::Limits::MINUTES
      return errors.add("minutes must be an array of #{sizes.min} to #{sizes.max} entries") unless list?(minutes, sizes)

      minutes.each_with_index { |entry, index| check_minute(entry, "minutes[#{index}]", errors) }
    end

    def check_minute(entry, path, errors)
      return errors.add("#{path} must be an object") unless entry.is_a?(Hash)

      errors.add("#{path}.minute must be the UTC start of a minute") unless minute(entry["minute"])
      transactions = entry["transactions"]
      sizes = Apm::Limits::TRANSACTIONS_PER_MINUTE
      unless list?(transactions, sizes)
        return errors.add("#{path}.transactions must be an array of #{sizes.min} to #{sizes.max} entries")
      end

      transactions.each_with_index do |transaction, index|
        break if errors.full?

        Apm::MetricsEnvelope::TransactionCheck.new(transaction, "#{path}.transactions[#{index}]").check(errors)
      end
    end
end
