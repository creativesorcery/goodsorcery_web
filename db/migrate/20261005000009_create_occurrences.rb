class CreateOccurrences < ActiveRecord::Migration[8.1]
  def change
    create_table :occurrences do |t|
      t.references :issue, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.uuid :uuid, null: false
      t.datetime :occurred_at, null: false
      t.datetime :received_at, null: false
      t.string :environment, null: false
      t.string :release
      t.string :level, null: false
      t.string :user_digest, limit: 64
      t.text :payload, null: false
      t.datetime :created_at, null: false
    end

    add_index :occurrences, %i[project_id uuid], unique: true
    add_index :occurrences, %i[issue_id id]
    add_index :occurrences, %i[project_id received_at]
  end
end
