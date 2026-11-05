# One transaction's merged histogram for one UTC minute (docs/ARCHITECTURE.md
# §13.2), written by addition (Apm::StatsUpsert) and kept KEPT_FOR: it feeds
# the short ranges, the 1d chart and every "last hour" figure.
class ApmMinuteStat < ApplicationRecord
  KEPT_FOR = 2.days

  self.primary_key = %i[apm_transaction_id minute]

  belongs_to :apm_transaction, inverse_of: :apm_minute_stats

  def self.time_column = :minute
end
