# Error retention becomes a choice of 30, 60 or 90 days
# (Project::RETENTION_CHOICES, docs/ARCHITECTURE.md §12.2.3). Every app on
# another value moves to the nearest choice, a tie going to the longer one
# and anything under 30 days to 30, the rule Account::ProjectRetention uses.
# Retention was capped at 30 days, so in practice every such app moves to
# 30: allowed everywhere, as the hosted default retention_days is [30].
#
# The old values aren't restored on rollback: they can't be told apart from
# apps that chose 30.
class FitProjectRetentionToChoices < ActiveRecord::Migration[8.1]
  NEAREST_CHOICE = "CASE WHEN retention_days * 2 < 90 THEN 30 WHEN retention_days * 2 < 150 THEN 60 ELSE 90 END".freeze

  def up
    execute "UPDATE projects SET retention_days = #{NEAREST_CHOICE} WHERE retention_days NOT IN (30, 60, 90)"
  end

  def down
  end
end
