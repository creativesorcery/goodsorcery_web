# The monthly event quota becomes the monthly_event_quota entitlement
# (docs/ARCHITECTURE.md §12.2.2). Every quota set in the old column is copied
# into entitlement_values, unless the account already stores that key. A null
# column (no quota) copies nothing: hosted accounts then get the hosted
# default, and self-hosted ones stay unlimited.
#
# The column stays for this release: Account ignores it (ignored_columns) and
# a later release drops it. The previous release still selects and inserts it
# while this one boots (db:prepare runs before the switch), and again after
# `bin/kamal rollback` or a revert on main, neither of which runs down.
#
# Rolling back copies the stored values back into the column and removes the
# key again.
class MoveMonthlyEventQuotaToEntitlements < ActiveRecord::Migration[8.1]
  COPY_TO_ENTITLEMENTS = <<~SQL.squish.freeze
    UPDATE accounts
    SET entitlement_values = entitlement_values || jsonb_build_object('monthly_event_quota', monthly_event_quota)
    WHERE monthly_event_quota IS NOT NULL AND NOT entitlement_values ? 'monthly_event_quota'
  SQL

  # A stored null (no quota) or a value the column can't hold copies back as null.
  COPY_TO_COLUMN = <<~SQL.squish.freeze
    UPDATE accounts
    SET monthly_event_quota = CASE
          WHEN jsonb_typeof(entitlement_values -> 'monthly_event_quota') = 'number'
            AND (entitlement_values ->> 'monthly_event_quota') ~ '^[1-9][0-9]{0,17}$'
          THEN (entitlement_values ->> 'monthly_event_quota')::bigint
        END,
        entitlement_values = entitlement_values - 'monthly_event_quota'
    WHERE entitlement_values ? 'monthly_event_quota'
  SQL

  def up
    execute COPY_TO_ENTITLEMENTS
  end

  def down
    execute COPY_TO_COLUMN
  end
end
