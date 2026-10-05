class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    create_table :accounts do |t|
      t.string :name, null: false
      t.bigint :monthly_event_quota
      t.timestamps
    end
  end
end
