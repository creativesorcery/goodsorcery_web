class CreateIssueUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :issue_users, primary_key: %i[issue_id user_digest] do |t|
      t.bigint :issue_id, null: false
      t.bigint :project_id, null: false
      t.string :user_digest, limit: 64, null: false
      t.string :identity_digests, array: true, null: false, default: []
      t.integer :events_count, null: false, default: 0
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
    end
    add_foreign_key :issue_users, :issues, on_delete: :cascade
    add_foreign_key :issue_users, :projects, on_delete: :cascade
    add_index :issue_users, %i[project_id last_seen_at]
    add_index :issue_users, :identity_digests, using: :gin
  end
end
