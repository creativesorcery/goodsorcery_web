# Indexes for review findings: rollup retention deletes by hour, the
# overview's last-seen lookups and retention by issues.last_seen_at, and the
# issue list's "Users" sort. Built concurrently so ingest keeps writing.
class AddRetentionAndOverviewIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :issue_hourly_counts, :hour, algorithm: :concurrently, if_not_exists: true
    add_index :project_hourly_counts, :hour, algorithm: :concurrently, if_not_exists: true
    add_index :issues, %i[project_id last_seen_at], algorithm: :concurrently, if_not_exists: true
    add_index :issues, %i[project_id status users_count], algorithm: :concurrently, if_not_exists: true
  end
end
