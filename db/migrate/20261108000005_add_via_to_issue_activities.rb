# Marks issue activity made through the MCP endpoint ("via MCP" on the issue
# page). Nil means the dashboard (or ingest, for system entries).
class AddViaToIssueActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :issue_activities, :via, :string
  end
end
