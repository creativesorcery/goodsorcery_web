class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :memberships, %i[account_id user_id], unique: true
  end
end
