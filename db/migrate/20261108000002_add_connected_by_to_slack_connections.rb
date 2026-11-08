# Who pasted an app's Slack webhook URL and when (docs/ARCHITECTURE.md §11.5).
#
# - connected_by_user_id is shown on Settings › Alerts ("Connected by Jo on
#   Nov 8"), so owners can tell whose channel receives the alerts. Nullified
#   if the user is deleted.
# - connected_at is stamped whenever a URL is pasted, the same one again
#   included. A rejection is applied only while it is unchanged, so a post
#   to a replaced URL can't turn off its replacement.
class AddConnectedByToSlackConnections < ActiveRecord::Migration[8.1]
  def change
    add_reference :slack_connections, :connected_by_user, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :slack_connections, :connected_at, :datetime
  end
end
