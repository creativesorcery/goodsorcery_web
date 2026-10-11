# A member's own choices for one app's alert emails. Rows are sparse: no row
# means the defaults (alerts on, digest on). Deleting the membership or the
# app deletes them.
class CreateNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_preferences do |t|
      t.references :membership, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :alerts_muted, null: false, default: false
      t.boolean :digest_enabled, null: false, default: true
      t.timestamps
    end
    add_index :notification_preferences, %i[membership_id project_id], unique: true
  end
end
