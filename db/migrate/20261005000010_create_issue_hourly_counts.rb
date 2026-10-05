class CreateIssueHourlyCounts < ActiveRecord::Migration[8.1]
  def change
    create_table :issue_hourly_counts, primary_key: %i[issue_id hour] do |t|
      t.bigint :issue_id, null: false
      t.datetime :hour, null: false
      t.integer :count, null: false, default: 0
    end
    add_foreign_key :issue_hourly_counts, :issues, on_delete: :cascade
  end
end
