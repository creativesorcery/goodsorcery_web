# Staff can open the /staff area (accounts, users, entitlements). Granted
# with bin/rails goodsorcery:make_staff EMAIL=…, or by another staff member.
class AddStaffToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :staff, :boolean, null: false, default: false
  end
end
