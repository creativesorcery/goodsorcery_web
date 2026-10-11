# When an issue first seen in another environment (staging, preview…) was
# first seen in production. Set once by ingest (Ingest::IssueTally); existing
# issues are not backfilled, since when they reached production is unknown.
class AddReachedProductionAtToIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :issues, :reached_production_at, :datetime
  end
end
