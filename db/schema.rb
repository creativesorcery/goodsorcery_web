# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_03_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "monthly_event_quota"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "entitlement_values", default: {}, null: false
  end

  create_table "alert_deliveries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "project_id", null: false
    t.bigint "issue_id"
    t.string "kind", null: false
    t.string "dedupe_key", null: false
    t.string "status", default: "sent", null: false
    t.datetime "summarized_at"
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_alert_deliveries_on_created_at"
    t.index ["issue_id", "kind", "created_at"], name: "index_alert_deliveries_on_issue_id_and_kind_and_created_at"
    t.index ["project_id"], name: "index_alert_deliveries_on_project_id"
    t.index ["user_id", "created_at"], name: "index_alert_deliveries_awaiting_summary", where: "(((status)::text = 'folded'::text) AND (summarized_at IS NULL))"
    t.index ["user_id", "dedupe_key"], name: "index_alert_deliveries_on_user_id_and_dedupe_key", unique: true
    t.index ["user_id", "status", "created_at"], name: "index_alert_deliveries_on_user_id_and_status_and_created_at"
  end

  create_table "alert_rules", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "kind", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "threshold"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "enabled"], name: "index_alert_rules_on_kind_and_enabled"
    t.index ["project_id", "kind"], name: "index_alert_rules_on_project_id_and_kind", unique: true
    t.check_constraint "threshold IS NULL OR threshold >= 1 AND threshold <= 100000", name: "alert_rules_threshold_range"
  end

  create_table "api_keys", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "environment", null: false
    t.text "token", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.string "token_last4", null: false
    t.bigint "created_by_id"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_api_keys_on_created_by_id"
    t.index ["project_id", "environment"], name: "index_api_keys_on_project_id_and_environment", unique: true
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "inbound_events", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "api_key_id", null: false
    t.string "environment", null: false
    t.uuid "event_uuid", null: false
    t.text "body", null: false
    t.datetime "received_at", null: false
    t.index ["api_key_id"], name: "index_inbound_events_on_api_key_id"
    t.index ["project_id"], name: "index_inbound_events_on_project_id"
    t.index ["received_at"], name: "index_inbound_events_on_received_at"
  end

  create_table "issue_activities", force: :cascade do |t|
    t.bigint "issue_id", null: false
    t.bigint "user_id"
    t.string "kind", null: false
    t.bigint "subject_user_id"
    t.text "body"
    t.datetime "created_at", null: false
    t.index ["issue_id", "created_at"], name: "index_issue_activities_on_issue_id_and_created_at"
    t.index ["subject_user_id"], name: "index_issue_activities_on_subject_user_id"
    t.index ["user_id"], name: "index_issue_activities_on_user_id"
  end

  create_table "issue_hourly_counts", primary_key: ["issue_id", "hour"], force: :cascade do |t|
    t.bigint "issue_id", null: false
    t.datetime "hour", null: false
    t.integer "count", default: 0, null: false
    t.index ["hour"], name: "index_issue_hourly_counts_on_hour"
  end

  create_table "issue_tag_counts", primary_key: ["issue_id", "key", "value_digest"], force: :cascade do |t|
    t.bigint "issue_id", null: false
    t.string "key", limit: 32, null: false
    t.string "value_digest", limit: 64, null: false
    t.text "value", null: false
    t.bigint "count", default: 0, null: false
  end

  create_table "issue_users", primary_key: ["issue_id", "user_digest"], force: :cascade do |t|
    t.bigint "issue_id", null: false
    t.bigint "project_id", null: false
    t.string "user_digest", limit: 64, null: false
    t.string "identity_digests", default: [], null: false, array: true
    t.integer "events_count", default: 0, null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.index ["identity_digests"], name: "index_issue_users_on_identity_digests", using: :gin
    t.index ["project_id", "last_seen_at"], name: "index_issue_users_on_project_id_and_last_seen_at"
  end

  create_table "issues", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.integer "number", null: false
    t.string "fingerprint", limit: 64, null: false
    t.string "exception_class", null: false
    t.text "message", default: "", null: false
    t.string "culprit", limit: 500
    t.string "transaction_name"
    t.string "level", default: "error", null: false
    t.string "status", default: "unresolved", null: false
    t.string "environments", default: [], null: false, array: true
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "regressed_at"
    t.datetime "resolved_at"
    t.bigint "events_count", default: 0, null: false
    t.integer "users_count", default: 0, null: false
    t.bigint "assignee_id"
    t.virtual "search_text", type: :text, as: "lower((((((((exception_class)::text || ' '::text) || message) || ' '::text) || COALESCE((culprit)::text, ''::text)) || ' '::text) || COALESCE((transaction_name)::text, ''::text)))", stored: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "reached_production_at"
    t.index ["assignee_id"], name: "index_issues_on_assignee_id"
    t.index ["environments"], name: "index_issues_on_environments", using: :gin
    t.index ["project_id", "fingerprint"], name: "index_issues_on_project_id_and_fingerprint", unique: true
    t.index ["project_id", "first_seen_at"], name: "index_issues_on_project_id_and_first_seen_at"
    t.index ["project_id", "last_seen_at"], name: "index_issues_on_project_id_and_last_seen_at"
    t.index ["project_id", "number"], name: "index_issues_on_project_id_and_number", unique: true
    t.index ["project_id", "status", "events_count"], name: "index_issues_on_project_id_and_status_and_events_count"
    t.index ["project_id", "status", "last_seen_at"], name: "index_issues_on_project_id_and_status_and_last_seen_at"
    t.index ["project_id", "status", "users_count"], name: "index_issues_on_project_id_and_status_and_users_count"
    t.index ["search_text"], name: "index_issues_on_search_text", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "index_memberships_on_account_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "notification_preferences", force: :cascade do |t|
    t.bigint "membership_id", null: false
    t.bigint "project_id", null: false
    t.boolean "alerts_muted", default: false, null: false
    t.boolean "digest_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["membership_id", "project_id"], name: "index_notification_preferences_on_membership_id_and_project_id", unique: true
    t.index ["project_id"], name: "index_notification_preferences_on_project_id"
  end

  create_table "occurrences", force: :cascade do |t|
    t.bigint "issue_id", null: false
    t.bigint "project_id", null: false
    t.uuid "uuid", null: false
    t.datetime "occurred_at", null: false
    t.datetime "received_at", null: false
    t.string "environment", null: false
    t.string "release"
    t.string "level", null: false
    t.string "user_digest", limit: 64
    t.text "payload", null: false
    t.datetime "created_at", null: false
    t.index ["issue_id", "id"], name: "index_occurrences_on_issue_id_and_id"
    t.index ["project_id", "received_at"], name: "index_occurrences_on_project_id_and_received_at"
    t.index ["project_id", "uuid"], name: "index_occurrences_on_project_id_and_uuid", unique: true
  end

  create_table "project_hourly_counts", primary_key: ["project_id", "environment", "hour"], force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "environment", null: false
    t.datetime "hour", null: false
    t.bigint "count", default: 0, null: false
    t.index ["hour"], name: "index_project_hourly_counts_on_hour"
    t.index ["project_id", "hour"], name: "index_project_hourly_counts_on_project_id_and_hour"
  end

  create_table "projects", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "platform", default: "rails", null: false
    t.string "runtime_label"
    t.string "issue_prefix", null: false
    t.integer "issues_sequence", default: 0, null: false
    t.string "color", default: "iris", null: false
    t.string "scrub_fields", default: [], null: false, array: true
    t.integer "retention_days", default: 30, null: false
    t.datetime "first_event_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "default_environment"
    t.string "alert_scope", default: "default", null: false
    t.string "alert_selected_environments", default: [], null: false, array: true
    t.index ["account_id", "slug"], name: "index_projects_on_account_id_and_slug", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sessions_on_account_id"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "uptime_checks", force: :cascade do |t|
    t.bigint "uptime_monitor_id", null: false
    t.datetime "checked_at", null: false
    t.string "status", null: false
    t.integer "response_time_ms"
    t.integer "http_status"
    t.string "error_kind"
    t.index ["uptime_monitor_id", "checked_at"], name: "index_uptime_checks_on_uptime_monitor_id_and_checked_at"
    t.check_constraint "status::text = ANY (ARRAY['up'::character varying, 'down'::character varying]::text[])", name: "uptime_checks_status_check"
  end

  create_table "uptime_hourly_counts", primary_key: ["uptime_monitor_id", "hour"], force: :cascade do |t|
    t.bigint "uptime_monitor_id", null: false
    t.datetime "hour", null: false
    t.integer "checks_count", default: 0, null: false
    t.integer "up_count", default: 0, null: false
    t.bigint "response_time_ms_sum", default: 0, null: false
    t.index ["hour"], name: "index_uptime_hourly_counts_on_hour"
  end

  create_table "uptime_incidents", force: :cascade do |t|
    t.bigint "uptime_monitor_id", null: false
    t.datetime "started_at", null: false
    t.datetime "resolved_at"
    t.string "error_kind"
    t.integer "http_status"
    t.index ["resolved_at"], name: "index_uptime_incidents_on_resolved_at"
    t.index ["uptime_monitor_id", "started_at"], name: "index_uptime_incidents_on_uptime_monitor_id_and_started_at"
    t.index ["uptime_monitor_id"], name: "index_uptime_incidents_one_open", unique: true, where: "(resolved_at IS NULL)"
  end

  create_table "uptime_monitors", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.text "url", null: false
    t.integer "interval_minutes", default: 10, null: false
    t.string "status", default: "pending", null: false
    t.datetime "next_check_at", null: false
    t.datetime "last_checked_at"
    t.integer "last_response_time_ms"
    t.integer "last_http_status"
    t.string "last_error_kind"
    t.datetime "down_since"
    t.datetime "paused_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["next_check_at"], name: "index_uptime_monitors_due", where: "(paused_at IS NULL)"
    t.index ["project_id", "name"], name: "index_uptime_monitors_on_project_id_and_name"
    t.check_constraint "interval_minutes = ANY (ARRAY[1, 5, 10, 60])", name: "uptime_monitors_interval_minutes_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'up'::character varying, 'down'::character varying]::text[])", name: "uptime_monitors_status_check"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.string "time_zone", default: "UTC", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "email_verified_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "alert_deliveries", "issues", on_delete: :cascade
  add_foreign_key "alert_deliveries", "projects", on_delete: :cascade
  add_foreign_key "alert_deliveries", "users", on_delete: :cascade
  add_foreign_key "alert_rules", "projects", on_delete: :cascade
  add_foreign_key "api_keys", "projects", on_delete: :cascade
  add_foreign_key "api_keys", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "inbound_events", "api_keys", on_delete: :cascade
  add_foreign_key "inbound_events", "projects", on_delete: :cascade
  add_foreign_key "issue_activities", "issues", on_delete: :cascade
  add_foreign_key "issue_activities", "users", column: "subject_user_id", on_delete: :nullify
  add_foreign_key "issue_activities", "users", on_delete: :nullify
  add_foreign_key "issue_hourly_counts", "issues", on_delete: :cascade
  add_foreign_key "issue_tag_counts", "issues", on_delete: :cascade
  add_foreign_key "issue_users", "issues", on_delete: :cascade
  add_foreign_key "issue_users", "projects", on_delete: :cascade
  add_foreign_key "issues", "projects", on_delete: :cascade
  add_foreign_key "issues", "users", column: "assignee_id", on_delete: :nullify
  add_foreign_key "memberships", "accounts", on_delete: :cascade
  add_foreign_key "memberships", "users", on_delete: :cascade
  add_foreign_key "notification_preferences", "memberships", on_delete: :cascade
  add_foreign_key "notification_preferences", "projects", on_delete: :cascade
  add_foreign_key "occurrences", "issues", on_delete: :cascade
  add_foreign_key "occurrences", "projects", on_delete: :cascade
  add_foreign_key "project_hourly_counts", "projects", on_delete: :cascade
  add_foreign_key "projects", "accounts", on_delete: :cascade
  add_foreign_key "sessions", "accounts", on_delete: :cascade
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "uptime_checks", "uptime_monitors", on_delete: :cascade
  add_foreign_key "uptime_hourly_counts", "uptime_monitors", on_delete: :cascade
  add_foreign_key "uptime_incidents", "uptime_monitors", on_delete: :cascade
  add_foreign_key "uptime_monitors", "projects", on_delete: :cascade
end
