class CreateInboundEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :inbound_events do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :api_key, null: false, foreign_key: { on_delete: :cascade }
      t.string :environment, null: false
      t.uuid :event_uuid, null: false
      t.text :body, null: false
      t.datetime :received_at, null: false
    end
    add_index :inbound_events, :received_at
  end
end
