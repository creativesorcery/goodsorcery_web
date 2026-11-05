# Performance monitoring (docs/ARCHITECTURE.md §13.2): the transaction
# registry, per-minute and per-hour histogram rows merged by addition, the
# encrypted slow-request traces and the transient encrypted inbound batches.
# Every FK cascades, so deleting an app or a transaction deletes its data.
#
# - Stats arrays are dense: one entry per gs-v1 bucket (31), checked here.
# - apm_traces' unique [apm_transaction_id, minute] is the replacement
#   upsert's conflict target (one trace per transaction per minute).
# - apm_inbound_batches' unique [project_id, kind, uuid] makes a resent
#   batch_id a no-op.
class CreateApmTables < ActiveRecord::Migration[8.1]
  BUCKETS = 31
  ARRAYS = %i[bucket_counts bucket_db_ms bucket_http_ms bucket_view_ms bucket_ruby_ms queue_wait_counts].freeze

  def change
    create_apm_transactions
    create_stats_table(:apm_minute_stats, :minute)
    create_stats_table(:apm_hourly_stats, :hour)
    create_apm_traces
    create_apm_inbound_batches
  end

  private
    def create_apm_transactions
      create_table :apm_transactions do |t|
        t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.string :environment, null: false
        t.string :kind, null: false
        t.string :name, null: false, limit: 255
        t.boolean :total, null: false, default: false
        t.string :http_method, limit: 16
        t.string :route, limit: 255
        t.string :adapter, limit: 32
        t.string :queue, limit: 128
        t.string :source_file, limit: 500
        t.datetime :first_seen_at, null: false
        t.datetime :last_seen_at, null: false
        t.timestamps
        t.check_constraint "kind IN ('web', 'job')", name: "apm_transactions_kind_check"
      end
      add_index :apm_transactions, %i[project_id environment kind name], unique: true, name: "index_apm_transactions_registry"
      add_index :apm_transactions, %i[project_id environment kind last_seen_at], name: "index_apm_transactions_listing"
      add_index :apm_transactions, :last_seen_at
    end

    def create_stats_table(table, time_column)
      create_table table, primary_key: [ :apm_transaction_id, time_column ] do |t|
        t.bigint :apm_transaction_id, null: false
        t.datetime time_column, null: false
        t.bigint :requests_count, null: false, default: 0
        t.bigint :failed_count, null: false, default: 0
        t.float :duration_ms_sum, null: false, default: 0
        stats_arrays(t)
        t.float :queue_wait_ms_sum, null: false, default: 0
        ARRAYS.each { |column| t.check_constraint "cardinality(#{column}) = #{BUCKETS}", name: "#{table}_#{column}_size" }
      end
      add_foreign_key table, :apm_transactions, on_delete: :cascade
      add_index table, time_column
    end

    def stats_arrays(t)
      t.bigint :bucket_counts, array: true, null: false, default: [ 0 ] * BUCKETS
      %i[bucket_db_ms bucket_http_ms bucket_view_ms bucket_ruby_ms].each do |column|
        t.float column, array: true, null: false, default: [ 0.0 ] * BUCKETS
      end
      t.bigint :queue_wait_counts, array: true, null: false, default: [ 0 ] * BUCKETS
    end

    def create_apm_traces
      create_table :apm_traces do |t|
        t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :apm_transaction, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.uuid :uuid, null: false
        t.datetime :minute, null: false
        t.datetime :hour, null: false
        t.datetime :started_at, null: false, precision: 6
        %i[duration_ms db_ms http_ms view_ms ruby_ms].each { |column| t.float column, null: false, default: 0 }
        %i[sql_count http_count n_plus_one_count].each { |column| t.integer column, null: false, default: 0 }
        t.integer :status
        t.boolean :failed, null: false, default: false
        t.uuid :error_event_uuid
        t.text :payload, null: false # encrypted
        t.datetime :created_at, null: false
      end
      add_index :apm_traces, %i[project_id uuid], unique: true
      add_index :apm_traces, %i[apm_transaction_id minute], unique: true
      add_index :apm_traces, %i[apm_transaction_id started_at]
      add_index :apm_traces, :hour
    end

    def create_apm_inbound_batches
      create_table :apm_inbound_batches do |t|
        t.references :project, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.string :environment, null: false
        t.string :kind, null: false
        t.uuid :uuid, null: false
        t.text :body # encrypted; nil once processed
        t.datetime :received_at, null: false
        t.datetime :processed_at
        t.check_constraint "kind IN ('metrics', 'traces')", name: "apm_inbound_batches_kind_check"
      end
      add_index :apm_inbound_batches, %i[project_id kind uuid], unique: true
      add_index :apm_inbound_batches, :received_at
    end
end
