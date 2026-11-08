# Personal access tokens for the MCP endpoint (docs/ARCHITECTURE.md §14.1).
# One token covers one account and belongs to one of its members; only a
# SHA-256 digest of the token is stored (the plaintext is shown once). The
# membership is re-checked on every use, so no FK to memberships is needed.
class CreatePersonalAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_access_tokens do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :scopes, array: true, null: false, default: [ "read" ]
      t.string :token_digest, null: false
      t.string :token_last4, null: false
      t.datetime :expires_at
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :personal_access_tokens, :token_digest, unique: true
    add_index :personal_access_tokens, %i[user_id created_at]
  end
end
