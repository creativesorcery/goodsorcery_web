# One row per app and rule kind (new_issue, regression, reached_production,
# still_happening, daily_digest), each switched on or off on its own. Only
# still_happening uses a threshold (events in the last hour). Existing apps
# get the default rule set; plain SQL, so the migration never depends on the
# AlertRule model.
class CreateAlertRules < ActiveRecord::Migration[8.1]
  DEFAULTS = [
    [ "new_issue", true, nil ],
    [ "regression", true, nil ],
    [ "reached_production", true, nil ],
    [ "still_happening", true, 100 ],
    [ "daily_digest", false, nil ]
  ].freeze

  def up
    create_table :alert_rules do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :threshold
      t.timestamps
    end
    add_index :alert_rules, %i[project_id kind], unique: true
    add_index :alert_rules, %i[kind enabled]
    add_check_constraint :alert_rules, "threshold IS NULL OR threshold BETWEEN 1 AND 100000", name: "alert_rules_threshold_range"

    backfill_default_rules
  end

  def down
    drop_table :alert_rules
  end

  private
    def backfill_default_rules
      values = DEFAULTS.map { |kind, enabled, threshold| "(#{quote(kind)}, #{enabled}, #{threshold || 'NULL'}::integer)" }.join(", ")

      execute <<~SQL.squish
        INSERT INTO alert_rules (project_id, kind, enabled, threshold, created_at, updated_at)
        SELECT projects.id, defaults.kind, defaults.enabled, defaults.threshold, now(), now()
        FROM projects CROSS JOIN (VALUES #{values}) AS defaults (kind, enabled, threshold)
        ON CONFLICT (project_id, kind) DO NOTHING
      SQL
    end

    def quote(value) = connection.quote(value)
end
