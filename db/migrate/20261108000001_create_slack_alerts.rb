# Slack alerts (docs/ARCHITECTURE.md §11.5): one incoming-webhook connection
# per app, and a log of the posts decided for it (the Slack counterpart of
# alert_deliveries: throttle, hourly cap and audit, keyed per app).
#
# - slack_connections.webhook_url is encrypted (Active Record Encryption): the
#   URL is the credential. disabled_reason holds Slack's error code or an HTTP
#   status, never the URL.
# - slack_deliveries holds ids, the kind, a dedupe key and counts only. The
#   unique [project_id, dedupe_key] index makes a post race-safe: a second
#   job or sweep for the same alert inserts nothing and posts nothing.
class CreateSlackAlerts < ActiveRecord::Migration[8.1]
  def change
    create_slack_connections
    create_slack_deliveries
  end

  private
    def create_slack_connections
      create_table :slack_connections do |t|
        t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
        t.text :webhook_url, null: false # encrypted
        t.boolean :enabled, null: false, default: true
        t.datetime :disabled_at
        t.string :disabled_reason
        t.datetime :test_sent_at
        t.timestamps
      end
    end

    def create_slack_deliveries
      create_table :slack_deliveries do |t|
        t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :issue, foreign_key: { on_delete: :cascade }, index: false
        t.references :uptime_incident, foreign_key: { on_delete: :cascade }, index: false
        t.string :kind, null: false
        t.string :dedupe_key, null: false
        t.string :status, null: false, default: "sent"
        t.jsonb :summary_counts
        t.datetime :posted_at
        t.datetime :summarized_at
        t.datetime :created_at, null: false
        t.check_constraint "status IN ('sent', 'folded')", name: "slack_deliveries_status_check"
      end
      add_slack_delivery_indexes
    end

    def add_slack_delivery_indexes
      add_index :slack_deliveries, %i[project_id dedupe_key], unique: true
      add_index :slack_deliveries, %i[project_id status created_at]
      add_index :slack_deliveries, %i[issue_id kind created_at]
      add_index :slack_deliveries, :uptime_incident_id
      add_index :slack_deliveries, :created_at
      add_index :slack_deliveries, %i[project_id created_at], where: "status = 'folded' AND summarized_at IS NULL",
                name: "index_slack_deliveries_awaiting_summary"
    end
end
