# Reads a stored, already validated metrics body (Apm::MetricsEnvelope) into
# one Entry per transaction per minute, skipping minutes outside the accepted
# window (more than 24 hours old or more than 2 minutes ahead).
class Apm::MetricsPayload
  Entry = Data.define(:kind, :name, :labels, :minute, :distribution)

  def initialize(body)
    @data = JSON.parse(body)
  end

  def entries(now: Time.current)
    window = (now - Apm::Limits::METRICS_PAST)..(now + Apm::Limits::FUTURE)
    @data.fetch("minutes").flat_map do |minute_entry|
      minute = Apm::JsonShape.minute(minute_entry["minute"])
      window.cover?(minute) ? minute_entry.fetch("transactions").map { entry(it, minute) } : []
    end
  end

  private
    def entry(transaction, minute)
      Entry.new(kind: transaction["kind"], name: Apm::TransactionName.clean(transaction["kind"], transaction["name"]),
                labels: Apm::TransactionName.labels(transaction), minute:, distribution: distribution(transaction))
    end

    def distribution(transaction)
      Apm::Distribution.from_buckets(
        count: transaction["count"], failed: transaction["failed"], duration_ms: transaction["duration_ms"],
        buckets: transaction["buckets"], queue_wait: transaction["kind"] == "job" ? Array(transaction["queue_wait"]) : [],
        queue_wait_ms: transaction["kind"] == "job" ? transaction["queue_wait_ms"].to_f : 0.0
      )
    end
end
