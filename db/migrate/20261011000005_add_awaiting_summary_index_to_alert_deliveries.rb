# The hourly summary run (AlertSummary.deliver_due) looks for folded,
# unsummarized deliveries across all users. Those are normally none, so a
# partial index holding only them keeps the run from scanning the whole
# 30-day table. Built concurrently so alert jobs keep writing.
class AddAwaitingSummaryIndexToAlertDeliveries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :alert_deliveries, %i[user_id created_at],
      where: "status = 'folded' AND summarized_at IS NULL",
      name: "index_alert_deliveries_awaiting_summary",
      algorithm: :concurrently, if_not_exists: true
  end
end
