# One transaction's merged histogram for one UTC hour (docs/ARCHITECTURE.md
# §13.2), written by addition together with its minute row (no rollup job)
# and kept for the account's apm_retention_days.
class ApmHourlyStat < ApplicationRecord
  self.primary_key = %i[apm_transaction_id hour]

  belongs_to :apm_transaction, inverse_of: :apm_hourly_stats

  def self.time_column = :hour

  # { environment => requests } of an app's total rows since a time, for
  # picking the busiest environment.
  def self.requests_by_environment(project, since:)
    joins(:apm_transaction).merge(ApmTransaction.totals.where(project:)).where(hour: since..)
      .group("apm_transactions.environment").sum(:requests_count)
  end
end
