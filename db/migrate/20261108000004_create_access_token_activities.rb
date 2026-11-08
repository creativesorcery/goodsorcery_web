# The audit log of changes made through the MCP endpoint (docs/ARCHITECTURE.md
# §14.5): which token and member resolved, ignored or reopened which issues,
# or left a note. Ids and the action only, never captured data or note text.
class CreateAccessTokenActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :access_token_activities do |t|
      t.references :personal_access_token, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :action, null: false
      t.bigint :issue_ids, array: true, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_index :access_token_activities, %i[personal_access_token_id created_at], name: "index_access_token_activities_on_token_and_created_at"
  end
end
