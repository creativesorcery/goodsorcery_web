class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :environment, null: false
      t.text :token, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.string :token_last4, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :api_keys, :token_digest, unique: true
    add_index :api_keys, %i[project_id environment], unique: true
  end
end
