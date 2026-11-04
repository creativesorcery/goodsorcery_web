# Entitlement values per account (docs/ARCHITECTURE.md §12.2). Hosted mode
# reads them; self-hosted instances ignore them and every entitlement is
# unlimited. A future billing app pushes the values (§12.3).
class AddEntitlementValuesToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :entitlement_values, :jsonb, null: false, default: {}
  end
end
