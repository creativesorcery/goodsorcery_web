class CreateIssueActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :issue_activities do |t|
      t.references :issue, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.references :subject_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :body
      t.datetime :created_at, null: false
    end
    add_index :issue_activities, %i[issue_id created_at]
  end
end
