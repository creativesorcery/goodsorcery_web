class CreateIssues < ActiveRecord::Migration[8.1]
  SEARCH_TEXT = "lower(exception_class::text || ' ' || message || ' ' || " \
                "coalesce(culprit::text, '') || ' ' || coalesce(transaction_name::text, ''))"

  def change
    create_table :issues do |t|
      add_identity_columns(t)
      add_lifecycle_columns(t)
      t.virtual :search_text, type: :text, as: SEARCH_TEXT, stored: true
      t.timestamps
    end

    add_issue_indexes
  end

  private
    def add_identity_columns(t)
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :number, null: false
      t.string :fingerprint, limit: 64, null: false
      t.string :exception_class, null: false
      t.text :message, null: false, default: ""
      t.string :culprit, limit: 500
      t.string :transaction_name
      t.string :level, null: false, default: "error"
    end

    def add_lifecycle_columns(t)
      t.string :status, null: false, default: "unresolved"
      t.string :environments, array: true, null: false, default: []
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :regressed_at
      t.datetime :resolved_at
      t.bigint :events_count, null: false, default: 0
      t.integer :users_count, null: false, default: 0
      t.references :assignee, foreign_key: { to_table: :users, on_delete: :nullify }
    end

    def add_issue_indexes
      add_index :issues, %i[project_id fingerprint], unique: true
      add_index :issues, %i[project_id number], unique: true
      add_index :issues, %i[project_id status last_seen_at]
      add_index :issues, %i[project_id status events_count]
      add_index :issues, %i[project_id first_seen_at]
      add_index :issues, :environments, using: :gin
      add_index :issues, :search_text, using: :gin, opclass: :gin_trgm_ops
    end
end
