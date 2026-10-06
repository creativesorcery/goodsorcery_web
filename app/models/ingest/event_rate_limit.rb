# The per-key and per-account ingest allowances for one API key, counted in
# events: the single endpoint takes 1, a batch takes its event count, from the
# same counters. Admission is all or nothing across both counters.
class Ingest::EventRateLimit
  def initialize(credential)
    @counters = [
      Ingest::RateCounter.new("key", credential.id, limit: Ingest::Limits::RATE_PER_KEY),
      Ingest::RateCounter.new("account", credential.account_id, limit: Ingest::Limits::RATE_PER_ACCOUNT)
    ]
  end

  # Takes events from every counter, or from none (returning false) when any
  # of them would go over its limit.
  def admit?(events)
    return true if events.zero?

    admitted = @counters.take_while { it.take(events) }
    return true if admitted.size == @counters.size

    admitted.each { it.give_back(events) }
    false
  end

  # Returns events taken earlier by #admit? (a request refused later on).
  def give_back(events)
    @counters.each { it.give_back(events) }
  end
end
