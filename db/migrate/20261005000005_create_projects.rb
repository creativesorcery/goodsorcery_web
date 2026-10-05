class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.string :slug, null: false
      t.string :platform, null: false, default: "rails"
      t.string :runtime_label
      t.string :issue_prefix, null: false
      t.integer :issues_sequence, null: false, default: 0
      t.string :color, null: false, default: "iris"
      t.string :scrub_fields, array: true, null: false, default: []
      t.integer :retention_days, null: false, default: 90
      t.datetime :first_event_at
      t.timestamps
    end
    add_index :projects, %i[account_id slug], unique: true
  end
end
