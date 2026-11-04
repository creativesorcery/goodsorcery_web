# Uptime monitoring (docs/ARCHITECTURE.md §12.1): monitors per app, raw check
# results (short-lived), hourly rollups for the uptime percentages and status
# bars, and incidents (down periods, the alert dedupe unit). Every FK cascades,
# so deleting a monitor deletes its history.
#
# - index_uptime_monitors_due is the scheduler's only access path (§12.4).
# - index_uptime_incidents_one_open allows at most one open incident per monitor.
# - Check rows hold no URL, body, headers or exception message.
class CreateUptimeMonitors < ActiveRecord::Migration[8.1]
  def change
    create_uptime_monitors
    create_uptime_checks
    create_uptime_hourly_counts
    create_uptime_incidents
  end

  private
    def create_uptime_monitors
      create_table :uptime_monitors do |t|
        t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.string :name, null: false
        t.text :url, null: false # encrypted
        t.integer :interval_minutes, null: false, default: 10
        t.string :status, null: false, default: "pending"
        t.datetime :next_check_at, null: false
        t.datetime :last_checked_at
        t.integer :last_response_time_ms
        t.integer :last_http_status
        t.string :last_error_kind
        t.datetime :down_since
        t.datetime :paused_at
        t.timestamps
        t.check_constraint "interval_minutes IN (1, 5, 10, 60)", name: "uptime_monitors_interval_minutes_check"
        t.check_constraint "status IN ('pending', 'up', 'down')", name: "uptime_monitors_status_check"
      end
      add_index :uptime_monitors, %i[project_id name]
      add_index :uptime_monitors, :next_check_at, where: "paused_at IS NULL", name: "index_uptime_monitors_due"
    end

    def create_uptime_checks
      create_table :uptime_checks do |t|
        t.references :uptime_monitor, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.datetime :checked_at, null: false
        t.string :status, null: false
        t.integer :response_time_ms
        t.integer :http_status
        t.string :error_kind
        t.check_constraint "status IN ('up', 'down')", name: "uptime_checks_status_check"
      end
      add_index :uptime_checks, %i[uptime_monitor_id checked_at]
    end

    def create_uptime_hourly_counts
      create_table :uptime_hourly_counts, primary_key: %i[uptime_monitor_id hour] do |t|
        t.bigint :uptime_monitor_id, null: false
        t.datetime :hour, null: false
        t.integer :checks_count, null: false, default: 0
        t.integer :up_count, null: false, default: 0
        t.bigint :response_time_ms_sum, null: false, default: 0
      end
      add_foreign_key :uptime_hourly_counts, :uptime_monitors, on_delete: :cascade
      add_index :uptime_hourly_counts, :hour
    end

    def create_uptime_incidents
      create_table :uptime_incidents do |t|
        t.references :uptime_monitor, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.datetime :started_at, null: false
        t.datetime :resolved_at
        t.string :error_kind
        t.integer :http_status
      end
      add_index :uptime_incidents, %i[uptime_monitor_id started_at]
      add_index :uptime_incidents, :resolved_at
      add_index :uptime_incidents, :uptime_monitor_id, unique: true, where: "resolved_at IS NULL",
                name: "index_uptime_incidents_one_open"
    end
end
