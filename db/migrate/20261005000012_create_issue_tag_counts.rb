class CreateIssueTagCounts < ActiveRecord::Migration[8.1]
  def change
    create_table :issue_tag_counts, primary_key: %i[issue_id key value_digest] do |t|
      t.bigint :issue_id, null: false
      t.string :key, limit: 32, null: false
      t.string :value_digest, limit: 64, null: false
      t.text :value, null: false
      t.bigint :count, null: false, default: 0
    end
    add_foreign_key :issue_tag_counts, :issues, on_delete: :cascade
  end
end
