# One row per alert email decided for one recipient: the throttle and audit
# log. Holds ids, the rule kind and a dedupe key only, never captured data.
#
# - unique [user_id, dedupe_key] makes throttling race-safe: an
#   INSERT ... ON CONFLICT DO NOTHING that returns no row means "already sent"
#   (per issue per rule per window, per user per app per local day for the
#   digest, per user per hour for the overflow summary).
# - [user_id, status, created_at] counts a user's sent emails in the last hour
#   (the global cap) and finds folded ones awaiting the summary email.
# - [issue_id, kind, created_at] answers "was this issue alerted for this
#   rule recently?" before any per-user work, and serves the FK cascade.
class CreateAlertDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :alert_deliveries do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :issue, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.string :dedupe_key, null: false
      t.string :status, null: false, default: "sent"
      t.datetime :summarized_at
      t.datetime :created_at, null: false
    end
    add_index :alert_deliveries, %i[user_id dedupe_key], unique: true
    add_index :alert_deliveries, %i[user_id status created_at]
    add_index :alert_deliveries, %i[issue_id kind created_at]
    add_index :alert_deliveries, :created_at
  end
end
