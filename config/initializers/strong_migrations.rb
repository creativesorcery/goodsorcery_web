# Checks every new migration for operations that lock or rewrite tables, so
# upgrades stay safe on self-hosted databases of any size. The rules behind it
# are in docs/MIGRATIONS.md.

# Migrations up to this version shipped before the checks existed. Leave it
# alone: new migrations are always checked.
StrongMigrations.start_after = 20261108000005

# Run the checks for the oldest Postgres self-hosters may run (README:
# "14 or newer"), even though development and hosted run a newer one.
StrongMigrations.target_version = 14

# Fail fast instead of queueing behind ingest traffic. A migration that can't
# get its lock in time is retried, then fails, and the previous release keeps
# running. Statements themselves may run long.
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.lock_timeout_retries = 3
StrongMigrations.statement_timeout = 1.hour

# Refresh planner statistics after adding an index.
StrongMigrations.auto_analyze = true
