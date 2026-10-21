# Retention is capped at Project::MAX_RETENTION_DAYS (30). New apps default to
# 30 days, and apps set longer are lowered to 30; the next daily prune then
# deletes their older occurrences. The lowered values aren't restored on
# rollback, since the deleted data can't come back either.
class CapProjectRetentionAt30Days < ActiveRecord::Migration[8.1]
  def up
    change_column_default :projects, :retention_days, from: 90, to: 30
    execute "UPDATE projects SET retention_days = 30 WHERE retention_days > 30"
  end

  def down
    change_column_default :projects, :retention_days, from: 30, to: 90
  end
end
