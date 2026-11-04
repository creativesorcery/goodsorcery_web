# Down and recovered alerts for uptime monitors (docs/ARCHITECTURE.md §12.9):
# each member gets a third switch per app ("Uptime alerts"), and every
# existing app gets the two uptime rules, both on. Safe to run again: the
# column is added only if missing and the rules insert ON CONFLICT DO
# NOTHING. Plain SQL, so the migration never depends on the AlertRule model.
class AddUptimeAlerts < ActiveRecord::Migration[8.1]
  KINDS = %w[monitor_down monitor_recovered].freeze

  def up
    add_column :notification_preferences, :uptime_alerts_muted, :boolean, null: false, default: false, if_not_exists: true
    backfill_uptime_rules
  end

  def down
    execute "DELETE FROM alert_rules WHERE kind IN (#{KINDS.map { |kind| connection.quote(kind) }.join(', ')})"
    remove_column :notification_preferences, :uptime_alerts_muted, if_exists: true
  end

  private
    def backfill_uptime_rules
      values = KINDS.map { |kind| "(#{connection.quote(kind)})" }.join(", ")

      execute <<~SQL.squish
        INSERT INTO alert_rules (project_id, kind, enabled, threshold, created_at, updated_at)
        SELECT projects.id, defaults.kind, TRUE, NULL, now(), now()
        FROM projects CROSS JOIN (VALUES #{values}) AS defaults (kind)
        ON CONFLICT (project_id, kind) DO NOTHING
      SQL
    end
end
