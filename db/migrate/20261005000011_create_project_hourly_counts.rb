class CreateProjectHourlyCounts < ActiveRecord::Migration[8.1]
  def change
    create_table :project_hourly_counts, primary_key: %i[project_id environment hour] do |t|
      t.bigint :project_id, null: false
      t.string :environment, null: false
      t.datetime :hour, null: false
      t.bigint :count, null: false, default: 0
    end
    add_foreign_key :project_hourly_counts, :projects, on_delete: :cascade
    add_index :project_hourly_counts, %i[project_id hour]
  end
end
